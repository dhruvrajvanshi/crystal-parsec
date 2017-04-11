require "crz"
require "../src/parsec"
include Parsec

## JSON syntax tree.
## Uses CRZ algebraic data types for brevity
## This translates into a simple class hierarchy with JSON
## as an abstract base class and JNumber, JString, ..., etc
## as derived concrete classes containing values of types
## mentioned in the parens.
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
  array_p | bool_p | null_p | jstring_p | number_p | object_p
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
  string("null") >> Parser.of(JNull.new.as JSON)
end
def comma
  optional_whitespace >> char(',') >> optional_whitespace
end
def array_p
  mdo({
    _   <= char('['),
    arr <= sep_by(json_p.as Parser(JSON), comma),
    _   <= char(']'),
    Parser.of(JArray.new(arr))
  }).map {|a| a.as JSON }
end

def string_p
  mdo({
    _ <= char('"'),
    arr <= many(
        (string("\\\"").map {|x| "\""}) | # escaped quote
        (string("\\n").map {|x| "\n"}) | # escaped newline
        (string("\\\\").map {|x| "\\"}) | # escaped backslash
        (none_of("\"\\").map {|x| x.to_s}) # other characters
      ),
    _ <= char('"'),
    str = (arr.reduce {|prev, current| prev + current}),
    Parser.of(str)
  })
end

def jstring_p
  string_p.map {|s| JString.new(s).as(JSON)}
end

# concatenate elements of array into string
def concatenate(arr)
  result = ""
    arr.each do |char|
      result += char.to_s
    end
  result
end

def float_p
  mdo({
    before <= (many_1(digit).map {|a| concatenate(a) }),
    _ <= char('.'),
    after <= (many_1(digit).map {|a| concatenate(a)}),
    num = (before + "." + after).to_f,
    json = (JNumber.new num).as(JSON),
    Parser.of(json)
  })
end

def int_p
  many_1(digit).map {|a| concatenate(a)}
    .map(&.to_f)
    .map {|x| JNumber.new(x).as(JSON) }
end

def number_p
  int_p | float_p
end

def object_pair
  mdo({
    key <= string_p,
    _ <= optional_whitespace,
    _ <= char(':'),
    _ <= optional_whitespace,
    value <= json_p.as(Parser(JSON)),
    Parser.of({key, value})
  })
end

def create_object(arr : Array({String, JSON})) : Parser(JSON)
  map = {} of String => JSON
  arr.each do |tuple|
    if map[tuple[0]]?
      return Parsec.fail(JSON, "Duplicate key \"#{tuple[0]}\" in object")
    else
      map[tuple[0]] = tuple[1]
    end
  end
  Parser.of((JObject.new map).as(JSON))
end

def object_p
  mdo({
    _ <= (char('{') >> optional_whitespace),
    pairs <= sep_by(object_pair, comma),
    _ <= (optional_whitespace >> char('}')),
    create_object(pairs)
  })
end

pp object_p.parse("{
    \"key\": 23,
    \"key1\": {
      \"k\": [\"asdf\", 2, true, {}]
    }
  }
")