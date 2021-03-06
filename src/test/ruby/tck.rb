# Copyright (c) 2015, 2017 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
#
# Eclipse Public License version 1.0
# GNU General Public License version 2
# GNU Lesser General Public License version 2.1

Polyglot.export_method def plus_int(a, b)
  a + b
end

Polyglot.export_method def fourty_two
  42
end

Polyglot.export_method def ret_nil
  nil
end

$invocations = 0

Polyglot.export_method def count_invocations
  $invocations += 1
end

Polyglot.export_method def apply_numbers(f)
  f.call(18, 32) + 10
end

Polyglot.export_method def compound_object
  obj = Object.new

  def obj.fourtyTwo
    42
  end

  def obj.plus(a, b)
    a + b
  end

  def obj.returnsNull
    nil
  end

  def obj.returnsThis
    self
  end

  obj
end

Polyglot.export_method def identity(value)
  value
end

Polyglot.export_method def evaluate_source(mime, source)
  Truffle::Interop.eval(mime, source)
end

Polyglot.export_method def complex_add(a, b)
  a[:imaginary] = a[:imaginary] + b[:imaginary]
  a[:real] = a[:real] + b[:real]
end

Polyglot.export_method def complex_add_with_method(a, b)
  a[:imaginary] = a[:imaginary] + b[:imaginary]
  a[:real] = a[:real] + b[:real]
end

Polyglot.export_method def complex_sum_real(complexes)
  complexes = Polyglot.as_enumerable(complexes)
  
  complexes.map{ |c| c[:real] }.inject(&:+)
end

Polyglot.export_method def complex_copy(a, b)
  a = Polyglot.as_enumerable(a)
  b = Polyglot.as_enumerable(b)

  # TODO CS 21-Dec-15
  # If we don't force b to an array here, the zip below will try to iterate both a and b at the same time. It can't do
  # that with Ruby blocks, so it creates a Fiber (a Java thread) to do it using two separate call stacks. That causes
  # com.oracle.truffle.api.interop.ForeignAccess.checkThread(ForeignAccess.java:133) to fail. What do we do about this?
  b = b.to_a

  a.zip(b).each do |x, y|
    x[:imaginary] = y[:imaginary]
    x[:real] = y[:real]
  end
end

ValuesClass = Struct.new(:byteValue, :shortValue, :intValue, :longValue, :floatValue, :doubleValue, :charValue, :stringValue, :booleanValue)

Polyglot.export_method def values_object
  ValuesClass.new(0, 0, 0, 0, 0.0, 0.0, '0', '', false)
end

Polyglot.export_method def add_array(array, index, value)
  array[index] += value
end

Polyglot.export_method def count_up_while(f)
  counter = 0
  loop do
    break unless f.call(counter)
    counter += 1
  end
end

Polyglot.export_method def object_with_element
  [1, 2, 42.0, 4]
end

class ObjectWithValueProperty

  attr_accessor :value

  def initialize
    @value = 42.0
  end

end

Polyglot.export_method def object_with_value_property
  ObjectWithValueProperty.new
end

Polyglot.export_method def function_add_numbers
  proc do |a, b|
    a + b
  end
end

ObjectWithValueAndAddProperty = Struct.new(:value)

class ObjectWithValueAndAddProperty
  
  def add(other)
    value + other
  end

end

Polyglot.export_method def object_with_value_and_add_property
  ObjectWithValueAndAddProperty.new(42.0)
end

Polyglot.export_method def call_function(function)
  function.call 41.0, 42.0
end

Polyglot.export_method def call_method(object)
  object.foo 41.0, 42.0
end

Polyglot.export_method def read_value_from_foreign(object)
  object[:value]
end

Polyglot.export_method def read_element_from_foreign(object)
  object[2]
end

Polyglot.export_method def write_value_to_foreign(object)
  object[:value] = 42.0
end

Polyglot.export_method def write_element_to_foreign(object)
  object[2] = 42.0
end

Polyglot.export_method def get_size_of_foreign(object)
  object.size
end

Polyglot.export_method def has_size_of_foreign(object)
  object.respond_to?(:size)
end

Polyglot.export_method def is_null_foreign(object)
  object.nil?
end

Polyglot.export_method def is_executable_of_foreign(object)
  object.respond_to?(:call)
end


Polyglot.export_method def value_with_source
  -> {}
end


Polyglot.export_method def meta_objects_int
  42
end

Polyglot.export_method def meta_objects_int_metaclass
  'Fixnum'
end

Polyglot.export_method def meta_objects_str
  'Hello Meta'
end

Polyglot.export_method def meta_objects_str_metaclass
  'String'
end

Polyglot.export_method def meta_objects_proc
  -> {}
end

Polyglot.export_method def meta_objects_proc_metaclass
  'Proc'
end
