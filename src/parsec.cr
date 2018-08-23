require "crz"

module Parsec
  include CRZ::Monad::Macros
  extend self
  class ParseState
    getter input
    getter offset
    def initialize(@input : String, @offset : Int32)
    end

    def advance(by = 1) : ParseState
      ParseState.new @input, @offset + by
    end
  end

  class ParseError
    getter state
    getter message
    def initialize(@message : String, @state : ParseState)
    end

    def to_s
      @message
    end
  end

  adt ParseResult(T),
    Error(String),
    Success(T, ParseState)

  class Parser(A)
    include Monad(A)
    getter block
    def initialize(&block : ParseState -> ParseResult(A))
      @block = block
    end

    # Run this parser, returning either a `ParseError`, or
    # the result
    def parse(input : String) : (A | ParseError)
      initial_state = ParseState.new input, 0
      result = @block.call initial_state
      ParseResult.match result, ParseResult(A), {
        [Error, msg] => ParseError.new(msg, initial_state),
        [Success, value, new_state] => value
      }
    end

    # Sequence another parser after this parser.
    # Takes a function that takes the result of this
    # parser and returns a new parser using the result.
    # If this parser fails, parsing is short circuited
    def bind(&f : A -> Parser(B)) : Parser(B) forall B
      Parser(B).new do |state|
        ParseResult.match (@block.call state), ParseResult(A), {
          [Error, msg] => ParseResult::Error(B).new(msg),
          [Success, a, new_state] => f.call(a).block.call(new_state)
        }
      end
    end

    # Combine another parser of the same type with
    # this parser. If this parser fails, try using
    # the given parser.
    def |(p2 : Parser(A)) : Parser(A)
      f1 = @block
      f2 = p2.block
      Parser(A).new do |state|
        result = (f1.call state)
        ParseResult.match result, ParseResult(A), {
          [Success, _, _] => result,
          [Error, e] => f2.call state
        }
      end
    end

    # Sequence another parser after this parser,
    # ignoring the result of the second one, and returning
    # the result of this parser.
    #
    # ```
    # px = one_or_more(digit)
    #   .pass_through(string "px")
    #   .map {|x| x.join() }
    #   .map {|x| x.to_i }
    # px.parse("10px").should eq 10
    # px.parse("10").class.should eq ParseError
    # ```
    def pass_through(p : Parser(B)) : Parser(A) forall B
      mdo({
        result <= self,
        _ <= p,
        Parser.of(result)
      })
    end

    def self.of(v : T) : Parser(T) forall T
      Parser(T).new do |state|
        ParseResult::Success(T).new v, state
      end
    end
  end

  def fail(cls : T.class, message : String) : Parser(T) forall T
    Parser(T).new do |state|
      ParseResult::Error(T).new message
    end
  end

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

  def string(s : String) : Parser(String)
    if s.size == 0
      Parser.of ""
    elsif s.size == 1
      (char s[0]).map {|x| x.to_s}
    else
      x = s[0]
      xs = s[1...s.size]
      mdo({
        c <= char(x),
        rest <= string(xs).as(Parser(String)),
        Parser.of(x + rest)
      })
    end
  end

  def one_of(s : String) : Parser(Char)
    p = char s[0]
    (1...s.size).each do |i|
      p = p | (char s[i])
    end
    p
  end

  def none_of(s : String) : Parser(Char)
    Parser.new do |state|
      if state.offset >= state.input.size
        ParseResult::Error(Char).new "Expected none of '#{s}', found end of string."
      elsif s.includes? state.input[state.offset].to_s
        ParseResult::Error(Char).new "Expected none of '#{s}', found #{state.input[state.offset]}."
      else
        ParseResult::Success.new state.input[state.offset], state.advance
      end
    end
  end

  def many(p : Parser(T)) : Parser(Array(T)) forall T
    f = p.block
    Parser(Array(T)).new do |s|
      result = f.call s
      acc = [] of T
      state = s
      count = 1
      while result.is_a? ParseResult::Success(T)
        state = result.value1
        acc << result.value0
        result = f.call state
        count+=1
      end
      ParseResult::Success.new acc, state
    end
  end

  def one_or_more(p : Parser(T)) : Parser(Array(T)) forall T
    mdo({
      x <= p,
      xs <= many(p),
      Parser.of(xs.unshift x)
    })
  end

  # DEPRECATED: Use `one_or_more`
  def many_1(p : Parser(T)) : Parser(Array(T)) forall T
    one_or_more p
  end

  def sep_by(p : Parser(T), seperator : Parser(U)) : Parser(Array(T)) forall T, U
    mdo({
      x <= p,
      s <= seperator,
      xs <= sep_by(p, seperator).as Parser(Array(T)),
      Parser.of(xs.unshift x)
    }) |
    (p.map {|x| [x]}) |
    Parser.of([] of T)
  end

  def lowercase
    one_of "qwertyuiopasdfghjklzxcvbnm"
  end

  def uppercase 
    one_of "QWERTYUIOPASDFGHJKLZXCVBNM"
  end

  def alphabet
    lowercase | uppercase
  end

  def digit
    one_of "1234567890"
  end

  def alphanum
    digit | alphabet
  end
end