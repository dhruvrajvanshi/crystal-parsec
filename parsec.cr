require "crz"

module Parsec
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

    def parse(input : String) : (A | ParseError)
      initial_state = ParseState.new input, 0
      result = @block.call initial_state
      ParseResult.match result, ParseResult(A), {
        [Error, msg] => ParseError.new(msg, initial_state),
        [Success, value, new_state] => value
      }
    end

    def bind(&f : A -> Parser(B)) : Parser(B) forall B
      Parser(B).new do |state|
        ParseResult.match (@block.call state), ParseResult(A), {
          [Error, msg] => ParseResult::Error(B).new(msg),
          [Success, a, new_state] => f.call(a).block.call(new_state)
        }
      end
    end

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

    def pass_through(p : Parser(B)) : Parser(A) forall B
      mdo({
        result <= self,
        _ <= p,
        Parser.pure(result)
      })
    end

    def self.pure(v : T) : Parser(T) forall T
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
      Parser.pure ""
    elsif s.size == 1
      (char s[0]).map {|x| x.to_s}
    else
      x = s[0]
      xs = s[1...s.size]
      mdo({
        c <= char(x),
        rest <= string(xs).as(Parser(String)),
        Parser.pure(x + rest)
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
      puts count
      puts acc.to_s
      puts result.value0.to_s
      ParseResult::Success.new acc, state
    end
  end

  def many_1(p : Parser(T)) : Parser(Array(T)) forall T
    mdo({
      x <= p,
      xs <= many(p),
      Parser.pure(xs.unshift x)
    })
  end

  def sep_by(p : Parser(T), seperator : Parser(U)) : Parser(Array(T)) forall T, U
    mdo({
      x <= p,
      s <= seperator,
      xs <= sep_by(p, seperator).as Parser(Array(T)),
      Parser.pure(xs.unshift x)
    }) |
    (p.map {|x| [x]}) |
    Parser.pure([] of T)
  end
end

include Parsec

p = Parser(Int32).new do |state|
  ParseResult::Error(Int32).new "error"
end

puts (p.parse "asdf")

p3 = Parser.pure 3

puts (p3.parse "234")

cP = char 'c'

puts cP.parse("cd")

puts string("asfgd").parse("asf").to_s

puts fail(Int32, "Unknown").parse("asdf").to_s

f = (Parser.pure 13).map do |x|
  x + 2
end


puts f.parse("asdf").to_s

f2 = (string "asdf") >> (string "12")
puts f2.parse("12asdf").to_s

p4 = Parser.pure(3) >= (->(x : Int32) { Parser.pure(x + 1) })

puts p4.parse("asdf")


p = (string "asdf") | (string "qwer")

puts p.parse("qwder").to_s

puts (one_of "asdf").parse("4").to_s


p = many (string "asdf")
puts p.parse("asdfasdfasdfasdfaa").to_s

p = many_1 (string "asdf")
puts p.parse("").to_s

p = none_of "asdf"
puts p.parse("a").to_s # error
puts p.parse("q").to_s # q



## JSON

adt JSON,
  JNumber(Float64),
  JString(String),
  JBool(Bool),
  JArray(Array(JSON)),
  JObject(Hash(String, JSON)),
  JNull

alias JNumber = JSON::JNumber
alias JString = JSON::JString
alias JBool   = JSON::JBool
alias JArray  = JSON::JArray
alias JObject = JSON::JObject
alias JNull   = JSON::JNull


def whitespace
  many_1(one_of "\n\t ") 
end
def optional_whitespace
  many(one_of "\n\t ")
end
def json_p : Parser(JSON)
  array_p | bool_p | null_p
end

def bool_p 
  (true_p | false_p).map {|v| JBool.new v }
      .map {|v| v.as JSON }
end

def true_p
  (string "true").map {|_| true }
end
def false_p
  (string "false").map {|_| false }
end

def null_p
  string("null") >> Parser.pure(JNull.new.as JSON)
end
comma = optional_whitespace >> char(',') >> optional_whitespace

def array_p
  mdo({
    _   <= char('['),
    arr <= sep_by(json_p.as Parser(JSON), comma),
    _   <= char(']'),
    Parser.pure(JArray.new(arr))
  }).map {|a| a.as JSON }
end

def string_p
  string_char = (string("\\\"").map {|x| "\""}) | # escaped quote
        (string("\\n").map {|x| "\n"}) | # escaped newline
        (string("\\\\").map {|x| "\\"}) | # escaped backslash
        (none_of("\"\\").map {|x| x.to_s}) # other characters
  mdo({
    _ <= char('"'),
    arr <= many(
        string_char
      ),
    _ <= char('"'),
    x = "asdf",
    Parser.pure(arr.reduce {|prev, current| prev + current})
  })
end


# pp array_p.parse("[true , false, null, [null, true]]")
pp string_p.parse("\"a\\\\\\nsdf\"")
