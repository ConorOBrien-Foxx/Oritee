# Oritee

Compiling on Windows (should be cross platform):
```
dmd -g -w oritee.d -of=oritee.exe
```

Running programs:

```
oritee <src.txt
```

Planned features:
- standard input
- read source from file
- documentation

## Example

```py
ary fib 1
def fib [ n ]
  ifelse ( lesseq n 1 )
    n
    add ( fib sub n 1 ) ( fib sub n 2 )

let first-fibs mapn fib range 10
print first-fibs
#=> [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
print add 5 first-fibs
#=> [5, 6, 6, 7, 8, 10, 13, 18, 26, 39]
print mul [ 0 1 ] first-fibs
#=> [0, 1, 0, 2, 0, 5, 0, 13, 0, 34]
```