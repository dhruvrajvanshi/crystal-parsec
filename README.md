# crystal-parsec [![Build Status](https://travis-ci.org/dhruvrajvanshi/crystal-parsec.svg?branch=master)](https://travis-ci.org/dhruvrajvanshi/crystal-parsec)
This is a parsing library for the Crystal language inspired by the Haskell library
Parsec. It allows you to build parsers by combining smaller parsers.

It is based on the functional programming library
[crz](https://github.com/dhruvrajvanshi/crz) which
adds ADTs and monadic do notation to the language.

## Quickstart
```crystal
require "parsec"
include Parsec
```
### Basics
A ```Parser(T)``` is a parser that parses a value of type T.
```crystal
p : Parser(T)
```
You can call .parse method on a parser with an input string to parse.
It returns either a value of type T on successful parsing or a ```Parsec::ParseError```
with an error message (return type ```T | ParseError```.
```crystal
p.parse "some input string"
```
```ParseError``` has a .message field that gives a human readable error message.

### Basic parsers
The simplest parser is a char parser that parses and returns a single character.
It's type is ```Parser(Char)```
```crystal
p = char 'c'
p.parse("c") # => 'c'
p.parse("d").message # => 
```

```string``` parser parses a fixed string.
```crystal
string("asdf").parse("asdf") # => "asdf"
string("asdf").parse("x") # => ParseError("Expected character 'a', found 'x'")
```

```one_of``` takes a string and returns a parser that
matches one of the characters in the given string.
```crystal
one_of("abcd").parse("a") # => 'a'
one_of("abcd").parse("c") # => 'c'
one_of("abcd").parse("2") # => ParseError
```

```none_of``` takes a string and returns a parser that
matches all characters except the ones in the given string.
```crystal
none_of(" \n\t").parse("a") # => 'a'
```

```Parser.of``` takes a value and returns a parser that consumes no input,
and returns the given value unconditionally. What's the use of this
parser? It's useful for sequencing as you'll see later.
```crystal
Parser.of(2).parse("asdf") # => 2
Parser.of("asdf").parse("") # => "asdf"
```

```fail``` takes an error message and returns a parser that
unconditionally fails using the given message. This is useful for error 
handling.
### Combining parsers
#### Or combinator
The ```|``` operator on parsers returns a parser that matches both the
parser on it's LHS and RHS. It first tries the LHS, if it fails, then
tries RHS.
```crystal
digit = one_of "1234567890"
alphabet = one_of "qwertyuiopasdfghjklzxcvbnm"
alphanum = digit | alphabet
alphanum.parse("a") # => 'a'
alphanum.parse("1") # => '1'
```
Both sides of the ```|``` operator should be of the same type. You cannot,
for example combine a ```Parser(Char)``` and a ```Parser(String)```.

#### many
It takes a parser and returns a parser that parses 0 or more instances of
that parser. It's type is ```Parser(A) -> Parser(Array(A))```
```crystal
many(digit).parse("") # => []
many(digit).parse("1") # => ['1']
many(digit).parse("1234) # => ['1', '2', '3', '4']
```

#### many_1
It is like many, but it needs atleast one instance. It won't return
an empty array.

#### sep_by
It takes two parsers. It parses an array of first parser, seperated by
the second parser.
```crystal
sep_by(digit, char(','))
  .parse("1,2,3,4") # => ['1', '2', '3', '4']
```
#### Transforming the result of parsers
The .map method on parsers is used to transform the result of a given
parser using a given block. It takes a block and returns a parser that
parses using ```self``` and passes the result through the block.
```crystal
# take a char array and concatenate it's elements
# into a string
def concatenate(arr)
  result = ""
    arr.each do |char|
      result += char.to_s
    end
  result
end

puts many_1(digit)
  .map {|arr| concatenate(arr) } # concatenate
  .map {|x| x.to_i } # convert to int
  .parse("233") # => 233
```

#### Sequencing parsers
You can sequence multiple parsers using the bind method.
The type signature of bind is ```(A -> Parser(B)) : Parser(B)``` where
```Parser(A)``` is the type of the parser it is called on.
It takes the result of the parser it is called on, passes the result to
the supplied block and returns the result of the block. It is like map
but instead of taking a block that returns a value, it takes a block that
returns another parser. This is used when you want to parse using multiple
parsers in sequence possibly using the result of each step for the next.
```crystal
alphabets = many_1(alphabet).map {|arr| concatenate(arr) }
digits    = many_1(digit).map {|arr| concatenate(arr) }
  .map {|x| x.to_i }
parser = alphabets.bind do |name|
  digits.bind do |number|
    Parser.of({name, number})
  end
end
parser.parse("asdf23") # => {"asdf", 23}
```
When you want to sequence a lot of parsers, nested binds can become
tedious and unreadable. To solve this problem, you can flatten out
bind sequences using the [crz](https://github.com/dhruvrajvanshi/crz)
macro ```mdo```. Using the macro, the previous parser would look like
this
```crystal
mdo({
  name <= alphabets,
  number <= digits,
  Parser.of({name, number})
})
```
This is much more readable in sequences of multiple parsers.
You can use regular assignments in mdo blocks too.
```crystal
mdo({
  name <= alphabets,
  num_arr <= many_1(digit),
  concatenated = concatenate(num_arr),
  number = concatenated.to_i,
  Parser.of({name, number})
}).parse("asdf123") # => {"asdf", 123}
```
Use ```<=``` when the RHS is a parser and ```=``` when it is a normal
value.

Always make sure that the last line in an mdo block is wrapped in a
parser using Parser.of.

#### Mutual recursion
If you have multiple parsers that depend on each other, you can wrap
them in a block so that they can be referred to before definition.
```crystal
def value_p
  number_p | string_p | array_p
end

def array_p
  mdo({
    _ <= char('['),
    arr <= sep_by(value_p, char(',')),
    _ <= char(']')
    Parser.of(arr)
  })
end
```
For recursive and mutually recursive parsers, you may need to cast
parsers to their type because type inference may not be able to infer
their types.

For example, this is directly from the JSON example in the examples
directory.
```crystal
def json_p : Parser(JSON)
  array_p | bool_p | null_p | jstring_p | number_p | object_p
end

def array_p
  mdo({
    _   <= char('['),
    arr <= sep_by(json_p.as Parser(JSON), comma),
    _   <= char(']'),
    Parser.of(JArray.new(arr))
  }).map {|a| a.as JSON }
end
```
Notice that even though return type of json_p is annotated, it still
needs to be cast to Parser(JSON) when being used in array_p using .as
method.

#### Other combinators
The ```>>``` operator is used to sequence two parsers and discard the
result of the left parser, returning the result of the right parser.
```crystal
p = string("asdf") >> string("abcd")
p.parse("asdfabcd") # => "abcd"
```

The ```<<``` operator sequences parsers but returns the result of the
first parser, ignoring the result of second parser.
```crystal
p = string("asdf") << string("abcd")
p.parse("asdfabcd") # => "asdf"
```

### Custom parsers
You can create custom parsers by calling ```Parser.new``` with block
argument  of type `ParseState -> ParseResult(A)` where A is the result
type of your parser.
ParseState has two members, `.input` and `.offset`. `input`
is the input string and `offset` is the current index into the input
string.
ParseResult is an abstract base class with two constructors,
`ParseState::Error(A).new "Error message"`, indicating parse error,
and `ParseState::Success.new(result, new_state)` indicating success.
To create a new `ParseState` from an existing state, you can call the
`.advance` method with an integer argument indicating the number of
characters you want to advance by. If argument is not given, it advances
by one character. `advance`

For example, here's the implementation of the `char` function.
```crystal
def char(c : Char) : Parser(Char)
  Parser.new do |state|
    if state.offset >= state.input.size
      ParseResult::Error(Char).new "Expected '#{c}' found end of string"
    elsif state.input[state.offset] == c
      ParseResult::Success.new c, state.advance
    else
      ParseResult::Error(Char).new "Expected '#{c}' found '#{state.input[state.offset]}'"
    end
  end
end
```

Check out the [json example](https://github.com/dhruvrajvanshi/crystal-parsec/blob/master/examples/json.cr) for a partial JSON parser example.