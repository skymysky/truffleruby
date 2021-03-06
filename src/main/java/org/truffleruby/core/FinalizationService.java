/*
 * Copyright (c) 2013, 2018 Oracle and/or its affiliates. All rights reserved. This
 * code is released under a tri EPL/GPL/LGPL license. You can use it,
 * redistribute it and/or modify it under the terms of the:
 *
 * Eclipse Public License version 1.0
 * GNU General Public License version 2
 * GNU Lesser General Public License version 2.1
 */
package org.truffleruby.core;

import java.lang.ref.ReferenceQueue;
import java.lang.ref.WeakReference;
import java.util.Collection;
import java.util.Deque;
import java.util.LinkedList;
import java.util.Map;
import java.util.Map.Entry;
import java.util.WeakHashMap;

import org.truffleruby.RubyContext;
import org.truffleruby.core.thread.ThreadManager;
import org.truffleruby.language.control.RaiseException;
import org.truffleruby.language.control.TerminationException;

import com.oracle.truffle.api.object.DynamicObject;

public class FinalizationService {

    private static class Finalizer {

        private final Class<?> owner;
        private final Runnable action;
        private final DynamicObject root;

        public Finalizer(Class<?> owner, Runnable action, DynamicObject root) {
            this.owner = owner;
            this.action = action;
            this.root = root;
        }

        public Class<?> getOwner() {
            return owner;
        }

        public Runnable getAction() {
            return action;
        }

        public DynamicObject getRoot() {
            return root;
        }
    }

    private static class FinalizerReference extends WeakReference<Object> {

        /**
         * All accesses to this Deque must be synchronized by taking the
         * {@link FinalizationService} monitor, to avoid concurrent access.
         */
        private final Deque<Finalizer> finalizers = new LinkedList<>();

        public FinalizerReference(Object object, ReferenceQueue<? super Object> queue) {
            super(object, queue);
        }

        private void addFinalizer(Class<?> owner, Runnable action, DynamicObject root) {
            finalizers.addLast(new Finalizer(owner, action, root));
        }

        private void removeFinalizers(Class<?> owner) {
            finalizers.removeIf(f -> f.getOwner() == owner);
        }

        private Finalizer getFirstFinalizer() {
            return finalizers.pollFirst();
        }

        private void collectRoots(Collection<DynamicObject> roots) {
            for (Finalizer finalizer : finalizers) {
                final DynamicObject root = finalizer.getRoot();
                if (root != null) {
                    roots.add(root);
                }
            }
        }

    }

    private final RubyContext context;

    private final Map<Object, FinalizerReference> finalizerReferences = new WeakHashMap<>();
    private final ReferenceQueue<Object> finalizerQueue = new ReferenceQueue<>();

    private DynamicObject finalizerThread;

    public FinalizationService(RubyContext context) {
        this.context = context;
    }

    public void addFinalizer(Object object, Class<?> owner, Runnable action) {
        addFinalizer(object, owner, action, null);
    }

    public synchronized void addFinalizer(Object object, Class<?> owner, Runnable action, DynamicObject root) {
        FinalizerReference finalizerReference = finalizerReferences.get(object);

        if (finalizerReference == null) {
            finalizerReference = new FinalizerReference(object, finalizerQueue);
            finalizerReferences.put(object, finalizerReference);
        }

        finalizerReference.addFinalizer(owner, action, root);

        if (context.getOptions().SINGLE_THREADED) {

            drainFinalizationQueue();

        } else {

            /*
             * We can't create a new thread while the context is initializing or finalizing, as the
             * polyglot API locks on creating new threads, and some core loading does things such as
             * stat files which could allocate memory that is marked to be automatically freed and so
             * would want to start the finalization thread. So don't start the finalization thread if we
             * are initializing. We will rely on some other finalizer to be created to ever free this
             * memory allocated during startup, but that's a reasonable assumption and a low risk of
             * leaking a tiny number of bytes if it doesn't hold.
             */

            if (finalizerThread == null && !context.isPreInitializing() && context.isInitialized() && !context.isFinalizing()) {
                createFinalizationThread();
            }

        }
    }

    private final void drainFinalizationQueue() {
        while (true) {
            final FinalizerReference finalizerReference = (FinalizerReference) finalizerQueue.poll();

            if (finalizerReference == null) {
                break;
            }

            runFinalizer(finalizerReference);
        }
    }

    private void createFinalizationThread() {
        final ThreadManager threadManager = context.getThreadManager();
        finalizerThread = threadManager.createBootThread("finalizer");
        context.send(finalizerThread, "internal_thread_initialize");

        threadManager.initialize(finalizerThread, null, "finalizer", () -> {
            while (true) {
                final FinalizerReference finalizerReference = (FinalizerReference) threadManager.runUntilResult(null,
                        finalizerQueue::remove);

                runFinalizer(finalizerReference);
            }
        });
    }

    private void runFinalizer(FinalizerReference finalizerReference) {
        try {
            while (!context.isFinalizing()) {
                final Finalizer finalizer;
                synchronized (this) {
                    finalizer = finalizerReference.getFirstFinalizer();
                }
                if (finalizer == null) {
                    break;
                }
                final Runnable action = finalizer.getAction();
                action.run();
            }
        } catch (TerminationException e) {
            throw e;
        } catch (RaiseException e) {
            context.getCoreExceptions().showExceptionIfDebug(e.getException());
        } catch (Exception e) {
            // Do nothing, the finalizer thread must continue to process objects.
            if (context.getCoreLibrary().getDebug() == Boolean.TRUE) {
                e.printStackTrace();
            }
        }
    }

    public void runAllFinalizersOnExit() {
        for (Entry<Object, FinalizerReference> entry : finalizerReferences.entrySet()) {
            runFinalizer(entry.getValue());
        }
    }

    public synchronized void removeFinalizers(Object object, Class<?> owner) {
        final FinalizerReference finalizerReference = finalizerReferences.get(object);

        if (finalizerReference != null) {
            finalizerReference.removeFinalizers(owner);
        }
    }

    public synchronized void collectRoots(Collection<DynamicObject> roots) {
        for (FinalizerReference finalizerReference : finalizerReferences.values()) {
            finalizerReference.collectRoots(roots);
        }
    }

}
