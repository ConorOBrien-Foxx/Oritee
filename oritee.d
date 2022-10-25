import std.algorithm.comparison : max;
import std.algorithm.iteration : map, sum;
import std.algorithm.searching : all, any;
import std.array;
import std.ascii;
import std.conv : to;
import std.datetime.stopwatch;
import std.functional;
import std.range;
import std.stdio;
import std.sumtype;
import std.traits;
import std.typecons;

/*
StopWatch sw = StopWatch(AutoStart.no);

void lap(string msg) {
    auto time = sw.peek();
    writeln(msg, ": ", time);
    sw.reset();
}
*/

// TODO: work on direct streams?
private struct streamTokensResult(Range) {
    alias R = Unqual!Range;
    R input;
    // state info
    ubyte[] buffer;
    string build;
    bool firstRead = true;
    
    this(R i) {
        input = i;
    }
    
    @property bool empty() {
        return input.empty && build.length == 0;
    }
    
    private ubyte nextByte() {
        if(firstRead) {
            buffer = input.front();
            firstRead = false;
        }
        else {
            buffer.popFront();
        }
        if(!buffer.length) {
            buffer = input.front();
            input.popFront();
        }
        return buffer.front();
    }
    
    string front() {
        if(firstRead) {
            popFront();
        }
        return build;
    }
    
    bool skipWhitespace(ref ubyte b) {
        bool foundAny = false;
        while(!input.empty && b.isWhite) {
            b = nextByte();
            foundAny = true;
        }
        return foundAny;
    }
    bool skipComment(ref ubyte b) {
        if(b == '#') {
            while(!input.empty && b != '\n') {
                b = nextByte();
            }
            return true;
        }
        else {
            return false;
        }
    }
    
    void popFront() {
        build = "";
        if(input.empty) {
            return;
        }
        ubyte b = nextByte();
        // skip to the next word
        while(skipWhitespace(b) || skipComment(b)) {
            
        }
        // parse word
        while(!input.empty && !b.isWhite) {
            build ~= b;
            b = nextByte();
        }
        // this discards the final terminator if it exists
    }
}

auto streamTokens(Range, alias ChunkSize=4096)(Range r) {
    auto input = r.byChunk(ChunkSize);
    return streamTokensResult!(typeof(input))(input);
}

T[] recycleTo(T)(T[] left, uint size) {
    auto res = left.dup;
    if(res.length >= size) return res;
    uint i = 0;
    while(res.length < size) {
        res ~= left[i++ % left.length];
    }
    return res;
}

T[] vectorize(alias Op, T)(T[] left, T[] right) {
    alias fn = binaryFun!Op;
    uint longer = max(left.length, right.length);
    T[] lr = recycleTo(left, longer);
    T[] rr = recycleTo(right, longer);
    return zip(lr, rr)
        .map!(t => fn(t[0], t[1]))
        .map!T
        .array;
}

T[] vectorize(alias Op, T)(T[] left, T right) {
    return vectorize!Op(left, [right]);
}

T[] vectorize(alias Op, T)(T left, T[] right) {
    return vectorize!Op([left], right);
}

alias _AtomValue = SumType!(int, char, float, Atom[], AtomFn, string);
struct Atom {
    _AtomValue value;
    
    this(bool val) {
        value = val ? 1 : 0;
    }
    
    this(T)(T val) {
        value = val;
    }
    
    size_t toHash() const nothrow @safe {
        return value.match!(a => a.hashOf());
    }
    
    string toString() {
        return value.to!string;
    }
    
    bool truthiness() {
        return value.match!(a => !!a, _ => true);
    }
    
    Atom opBinary(string op)(Atom rhs) {
        enum aOpB = "a " ~ op ~ " b";
        return match!(
            (a, b) {
                auto result = mixin(aOpB);
                static if(op == "%") {
                    if(result < 0) {
                        result += b;
                    }
                }
                return Atom(result);
            },
            (a, b) => Atom(vectorize!aOpB(a, b)),
            (a, b) => Atom(vectorize!aOpB(Atom(a), b)),
            (a, b) => Atom(vectorize!aOpB(a, Atom(b))),
            (_1, _2) => assert(0),
        )(value, rhs.value);
    }
    
    bool opEquals(const Atom rhs) const {
        return match!(
            (a, b) => a == b,
            (_1, _2) => assert(0, "Cannot compare"),
        )(value, rhs.value);
    }
    
    // TODO: can I avoid two comparisons?
    int opCmp(ref const Atom rhs) const {
        return match!(
            (a, b) => a < b ? -1 : a > b ? 1 : 0,
            (_1, _2) => assert(0, "Cannot compare"),
        )(value, rhs.value);
    }
    
    Atom[] quoted() {
        return value.match!(
            (Atom[] s) => s[0].match!(
                (string _) => s,
                (AtomFn _) => s,
                _ => assert(0, "Not a quoted value: " ~ toString())
            ),
            _ => assert(0, "Not a quoted value: " ~ toString()),
        );
    }
    
    string quotedName() {
        return quoted()[0].match!(
            (string s) => s,
            (AtomFn f) => f.name,
            _ => assert(0, "Cannot obtain quoted name value from " ~ toString())
        );
    }
    
    alias value this;
}

enum Hold { None, Basic, Word }

struct AtomFn {
    string name = "<unknown>";
    uint arity;
    Atom delegate(Atom[]) fn;
    Hold[] hold;
    bool frozen = false; // i don't think we have to copy this?
    
    this(uint a, Atom delegate(Atom[]) f) {
        arity = a;
        fn = f;
    }
    this(uint a, Hold[] h, Atom delegate(Atom[]) f) {
        arity = a;
        hold = h;
        fn = f;
    }
    
    this(Atom nilad) {
        this(0, (Atom[] arr) => nilad);
    }
    this(Atom delegate(Atom) monad) {
        this(1, (Atom[] arr) => monad(arr[0]));
    }
    this(void delegate(Atom) vmonad) {
        this(1, (Atom[] arr) {
            vmonad(arr[0]);
            return arr[0];
        });
    }
    this(Atom delegate(Atom, Atom) dyad) {
        this(2, (Atom[] arr) => dyad(arr[0], arr[1]));
    }
    this(Atom delegate(Atom, Atom, Atom) triad) {
        this(3, (Atom[] arr) => triad(arr[0], arr[1], arr[2]));
    }
    
    Hold getHold(uint index) {
        return frozen
            ? Hold.Basic
            : index < hold.length
                ? hold[index]
                : Hold.None;
    }
    
    AtomFn dup() {
        return AtomFn(arity, hold.dup, fn).setName(name);
    }
    
    AtomFn setHeld(Hold[] h) {
        hold = h;
        return this;
    }
    
    AtomFn setName(string n) {
        name = n;
        return this;
    }
    
    Atom evaluate() {
        return fn([]);
    }
    Atom evaluate(Atom[] args) {
        assert(args.length == arity,
            "Got " ~ to!string(args.length) ~ " argument(s), expected " ~ to!string(arity));
        return fn(args);
    }
    Atom opCall(T...)(T args) {
        return evaluate(args);
    }
}

struct Context {
    Atom[string] varTable;
    AtomFn[string] fnTable;
    Atom[string] codeTable;
    
    Context dup() {
        return Context(varTable.dup, fnTable.dup, codeTable.dup);
    }
    
    void updateReferences(Atom code, string find, AtomFn next) {
        code.match!(
            (Atom[] a) {
                a[0].match!(
                    (AtomFn fn) {
                        // writeln("Looking at: ", fn.name);
                        if(fn.name == find) {
                            // writeln("Hit!");
                            a[0] = Atom(next);
                        }
                        Atom[] children = a[1].match!(
                            (Atom[] arr) => arr,
                            _ => assert(0, "Invalid children")
                        );
                        foreach(at; children) {
                            updateReferences(at, find, next);
                        }
                    },
                    (_) {},
                );
            },
            (_) {}
        );
    }
    
    void setFn(string name, AtomFn fn) {
        fnTable[name] = fn;
        // update all the existing references
        foreach(otherName, code; codeTable) {
            // writeln("Updating references for: ", otherName);
            updateReferences(code, name, fn);
        }
    }
}

Atom evalNested(Atom s, Context ctx) {
    import core.exception : AssertError;
    Atom[] arr;
    s.match!(
        (Atom[] s) {
            s[0].match!(
                (string _) { arr = s; },
                (AtomFn _) { arr = s; },
                (_) {}
            );
        },
        (_) {}
    );
    if(!arr.length) return s;
    assert(arr.length > 0, "Nothing to evaluate");
    // lap("Quote parse");
    Atom head = arr[0];
    return head.match!(
        (AtomFn fn) {
            Atom[] rest = arr[1].match!(
                (Atom[] d) => d,
                _ => assert(0, "Expected an array for rest"),
            );
            // lap("Head parse");
            return fn(rest
                .zip(iota(rest.length))
                .map!(a => fn.getHold(a[1]) != Hold.None ? a[0] : evalNested(a[0], ctx))
                .array
            );
        },
        (string s) {
            auto var = s in ctx.varTable;
            if(var) {
                return *var;
            }
            else {
                assert(0, "Cannot find variable " ~ s);
            }
        },
        _ => assert(0, "Cannot evaluate head " ~ to!string(head)),
    );
}

int main() {
    // sw.start();
    Context[] stack;
    ref Context getContext() {
        return stack.back;
    }
    ref Context makeContext() {
        stack ~= stack.back.dup;
        return getContext();
    }
    void endContext() {
        stack.popBack();
    }
    uint lambdaCount = 0;
    string getNewLambdaName() {
        return "-lambda-" ~ to!string(lambdaCount);
    }
    Context ctx;
    ctx.varTable = [
        "zero":     Atom(0),  "one":      Atom(1),
        "two":      Atom(2),  "three":    Atom(3),
        "four":     Atom(4),  "five":     Atom(5),
        "six":      Atom(6),  "seven":    Atom(6),
        "eight":    Atom(8),  "nine":     Atom(9),
        "ten":      Atom(10),
        "io":       Atom(0), // index origin
    ];
    ctx.fnTable = [
        "add":      AtomFn((a, b) => a + b),
        "sub":      AtomFn((a, b) => a - b),
        "mul":      AtomFn((a, b) => a * b),
        "div":      AtomFn((a, b) => a / b),
        "mod":      AtomFn((a, b) => a % b),
        "print":    AtomFn(a => writeln(a)),
        "less":     AtomFn((a, b) => a.opBinary!"<" (b)),
        "lesseq":   AtomFn((a, b) => a.opBinary!"<="(b)),
        "more":     AtomFn((a, b) => a.opBinary!">" (b)),
        "moreeq":   AtomFn((a, b) => a.opBinary!">="(b)),
        "size":     AtomFn(a => a.match!(
            a => Atom(a.length),
            _ => assert(0, "Cannot get size of " ~ to!string(_)),
        )),
        "cat":      AtomFn((a, b) => match!(
            (a, b) => Atom(a ~ b),
            (a, b) => Atom([Atom(a)] ~ b),
            (a, b) => Atom(a ~ [Atom(b)]),
            (a, b) => Atom([Atom(a)] ~ [Atom(b)]),
        )(a, b)),
        "get":      AtomFn((a, b) => match!(
            (a, b) {
                uint io = getContext().varTable["io"].match!(
                    val => cast(uint) val,
                    _ => assert(0, "Invalid index origin: " ~ to!string(_)),
                );
                auto result = a[b - io];
                static assert(is(typeof(result) == Atom));
                return result;
            },
            (_1, _2) => assert(0),
        )(a, b)),
        "let":      AtomFn((a, b) {
            string name = a.quotedName();
            return getContext().varTable[name] = b;
        }).setHeld([Hold.Word, Hold.None]),
        // for now, no difference
        "set":      AtomFn((a, b) {
            string name = a.quotedName();
            return getContext().varTable[name] = b;
        }).setHeld([Hold.Word, Hold.None]),
        // placeholder to define arity
        "ary":      AtomFn((a, b) {
            string name = a.quotedName();
            uint arity = b.match!(
                val => cast(uint) val,
                _ => assert(0, "Invalid arity: " ~ to!string(_))
            );
            return Atom(getContext().fnTable[name] = AtomFn(arity,
                (Atom[] a) => Atom(a)
            ).setName(name));
        }).setHeld([Hold.Word, Hold.None]),
        "def":      AtomFn((a, b, c) {
            // writeln("A: ", a);
            // writeln("B: ", b);
            // writeln("C: ", c);
            string name = a.quotedName();
            string[] args = b.quoted()[1].match!(
                (Atom[] a) => a.map!(e => e.quotedName()).array,
                _ => assert(0, "Expected arguments")
            );
            getContext().codeTable[name] = c;
            auto fn = AtomFn(args.length, (Atom[] a) {
                makeContext();
                
                foreach(name, val; args.zip(a)) {
                    getContext().varTable[name] = val;
                }
                Atom code = getContext().codeTable[name];
                Atom result = evalNested(code, getContext());
                
                endContext();
                
                return result;
            }).setName(name);
            getContext().setFn(name, fn);
            
            return Atom(fn);
        }).setHeld([Hold.Word, Hold.Basic, Hold.Basic]),
        "lambda":   AtomFn((a, b) {
            string name = getNewLambdaName();
            string[] args = a.quoted()[1].match!(
                (Atom[] a) => a.map!(e => e.quotedName()).array,
                _ => assert(0, "Expected arguments")
            );
            getContext().codeTable[name] = b;
            auto fn = AtomFn(args.length, (Atom[] a) {
                makeContext();
                
                foreach(name, val; args.zip(a)) {
                    getContext().varTable[name] = val;
                }
                Atom code = getContext().codeTable[name];
                Atom result = evalNested(code, getContext());
                
                endContext();
                
                return result;
            }).setName(name);
            getContext().setFn(name, fn);
            
            return Atom(fn);
        }).setHeld([Hold.Basic, Hold.Basic]),
        "ref":      AtomFn((a) {
            string name = a.quotedName();
            return Atom(getContext().fnTable[name]);
        }).setHeld([Hold.Word]),
        "call":     AtomFn((a, b) =>
            match!(
                (a, Atom[] args) => a(args),
                (a, _) => a([b]),
                (_1, _2) => assert(0, "Cannot call"),
            )(a, b)
        ).setHeld([Hold.None, Hold.None]),
        "map":      AtomFn((fn, arr) => match!(
            (AtomFn fn, Atom[] arr) => Atom(
                arr.map!(a => fn([a])).array
            ),
            (_1, _2) => assert(0, "Cannot map"),
        )(fn, arr)),
        "mapn":     AtomFn((a, arr) {
            string name = a.quotedName();
            auto fn = getContext().fnTable[name];
            return arr.match!(
                (Atom[] arr) => Atom(
                    arr.map!(a => fn([a])).array
                ),
                _ => assert(0, "Cannot map"),
            );
        }).setHeld([Hold.Word, Hold.None]),
        "range":    AtomFn(n => n.match!(
            n => Atom(n.iota.map!Atom.array),
            _ => assert(0, "Cannot range"),
        )),        
        "while":    AtomFn((a, b) {
            // writeln("Held A: ", a);
            // writeln("Held B: ", b);
            Atom ret = Atom(0);
            while(evalNested(a, getContext()).truthiness) {
                ret = evalNested(b, getContext());
            }
            return ret;
        }).setHeld([Hold.Basic, Hold.Basic]),
        "if":       AtomFn((a, b) {
            Atom ret = Atom(0);
            if(evalNested(a, getContext()).truthiness) {
                ret = evalNested(b, getContext());
            }
            return ret;
        }).setHeld([Hold.Basic, Hold.Basic]),
        "ifelse":   AtomFn((a, b, c) {
            if(evalNested(a, getContext()).truthiness) {
                return evalNested(b, getContext());
            }
            else {
                return evalNested(c, getContext());
            }
        }).setHeld([Hold.Basic, Hold.Basic, Hold.Basic]),
        "both":     AtomFn((a, b) => b),
        "[":        AtomFn(-1u, (Atom[] args) => Atom(args)),
        "(":        AtomFn(-1u, (Atom[] args) => args.back),
    ];
    ctx.fnTable["$"] = ctx.fnTable["ref"];
    foreach(k, ref v; ctx.fnTable) {
        v.name = k;
    }
    stack ~= ctx;
    
    
    Atom[][] data = [[]];
    AtomFn[] calls;
    // lap("Initialization");
    
    foreach(token; streamTokens(stdin)) {
        // write("Token: <", token, ">");
        
        Hold holdStatus = calls.empty || data.empty
            ? Hold.None
            : calls.back.getHold(data.back.length);
        // if(hold) {
            // write(" (held)");
        // }
        // writeln();
        
        auto fnPtr = token in getContext().fnTable;
        auto vrPtr = token in getContext().varTable;
        
        if(fnPtr && holdStatus != Hold.Word) {
            auto fn = (*fnPtr).dup;
            if(fn.arity == 0) {
                data.back ~= fn();
            }
            else {
                if(holdStatus != Hold.None) {
                    fn.frozen = true;
                }
                calls ~= fn;
                data ~= [[]];
            }
        }
        else {
            /*if(token == "(") {
                calls ~= getContext().fnTable["list"];
                if(hold) {
                    calls.back.frozen = true;
                }
                data ~= [[]];
            } else*/
            if(token == "]" || token == ")") {
                calls.back.arity = data.back.length;
            }
            else if(token.all!isDigit
                || token[0] == '-' && token[1..$].all!isDigit) {
                data.back ~= Atom(to!int(token));
            }
            else if(holdStatus != Hold.None) {
                data.back ~= Atom([Atom(token)]);
            }
            else if(vrPtr) {
                auto vr = *vrPtr;
                data.back ~= vr;
            }
            else {
                stderr.writeln("Unrecognized token: <", token, ">");
                return 1;
            }
        }
        
        // evaluate calls
        while(!calls.empty && data.back.length >= calls.back.arity) {
            // writeln(" call:   ", calls.back);
            // writeln(" frozen? ", calls.back.frozen);
            uint arity = calls.back.arity;
            Atom[] params = data.back[$ - arity..$];
            // writeln(" params: ", params);
            data.back.popBackN(arity);
            data.popBack;
            if(calls.back.frozen) {
                // depends on dup clearing frozen status
                data.back ~= Atom([Atom(calls.back.dup), Atom(params)]);
            }
            else {
                // sw.reset();
                data.back ~= calls.back()(params);
            }
            calls.popBack;
            // lap("Evaluation");
        }
    }
    
    return 0;
}
