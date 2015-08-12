# gensqlite
===========

Gensqlite is a bit of tooling for working with SQLite, implemented as a ppx
processor to generate prepared statements and query functions. This is based
off the excellent [SQLite3-OCaml](https://github.com/mmottl/sqlite3-ocaml/)
As such, there is minimal wrapping of SQLite3 types and functions, aside from a
few convenience functions in the auxiliary `Sqlite_tools` module.

### Installation
----------------

Via OPAM: `opam install gensqlite`. This will install `gensqlite` along with any
dependencies.

Manually, it can be used in the typical manner of a Makefile: `make`,
`make install`, `make uninstall`, `make clean`, as well as additional specific targets.
Sample code in both bytecode and native code is generated, and unit tests.
Any dependencies must be present on the system first:
[ppx_tools](https://github.com/alainfrisch/ppx_tools), [re](https://github.com/ocaml/ocaml-re), [sqlite3](https://github.com/mmottl/sqlite3-ocaml/) and [findlib](http://projects.camlcity.org/projects/findlib.html). [oUnit](http://ounit.forge.ocamlcore.org/) is not required when installing from OPAM, but needed for building unit tests.

Link `gensqlite` into applications using the `gensqlite.ppx` findlib package.

### License
-----------

LGPL 3.0 with OCaml linking exception. See LICENSE.

### Basic Usage
---------------

The `gensqlite` processor takes two parameters: an opened SQLite handle, and a
literal string query, then returns a prepared statement and a query function
parameterized by any necessary variable bindings. Here is a simple example:

```ocaml
open Sqlite_tools
let dbh = SQLite3.db_open "test.sqlite"
let (stmt, query) = [%gensqlite dbh "CREATE TABLE users(name TEXT UNIQUE, password TEXT, created INTEGER DEFAULT CURRENT_TIMESTAMP)"]
let () = query (); (* Voila! A new table is created! *)
```

The Sqlite_tools module contains utility functions that are called by the
`gensqlite` processor, and a few helper functions that can be used .

#### Error Handling

Since there is minimal wrapping of Sqlite3, any errors in the query, either
during preparation or execution, will raise a runtime error, usually of
`Sqlite3.Error`. For example, if we were to repeat the `query()` call from
above, it would fail. Therefore, if a crash+backtrace is not the desired
behavior, it is best to wrap each `gensqlite` and query invocation in a try
block:

```ocaml
try
  let (_, query) = [%gensqlite dbh "CREATE TABLE jobs(description TEXT)"]
  let () = query ()
  let () = query () (* will fail *)
with exn -> print_endline (Printexc.to_string exn)
```

Additionally, the `gensqlite` "parser" makes no attempt to validate the
incoming string as SQL, although a `Sqlite3.Error` will be thrown at runtime if
an invalid query is prepared. For example, the following statement will compile,
but will fail at runtime:

```ocaml
let _ = [%gensqlite dbh "hello world"]
```

### Direction and Typing
-------------------------

The query passed into `gensqlite` is actually pseudo-SQL which gets compiled to
'real' SQL. The differences are in the addition of annotations for variable
direction (input/output) and types.

Sigil | Meaning
------|--------
  >   | Input
  <   | Output
  @   | `string`
  :   | `int`
  ?   | `int32`
  $   | `int64`


The direction and type sigils must be used together; see the sections on Input
and Output.

#### Input

The generated query function has labelled arguments corresponding to the name of
the input(s).

```ocaml
let (_, insert) = [%gensqlite dbh "INSERT INTO users(name, password) VALUES(>@username, >@pass)"]
let () = insert ~username:"beakybird" ~pass:"supersecret" ()
```

Here, the labels `username` and `pass` correspond to the input variables in the
SQL query. Binding the variables to the statement is done automatically by
`gensqlite`.

#### Output

Output is a list of tuples, one tuple for each row, with tuple elements
corresponding to returned columns in the order that they were specified in the
query. If only a single output column is specified, then the results
will be primitive values; there will be no tuple to deconstruct.

Select example:

```ocaml
let (_, select) = [%gensqlite dbh "select <:rowid, <@name, strftime('%s', <?created) from users where name = >:name"]
let res = select ~name:"beakybird" ()
let print_res = function
  | (id, name, created) :: _ ->
    Printf.printf "id %d name %s created %ld\n" id name created
  | [] -> print_endline "Empty response" in
print_res res;

```

Notice the use of `strftime` here: SQLite built-in functions work well. The
timestamp is returned as an `int32` since integer Unix timestamps would
overflow an OCaml `int`.

Another example using aggregate functions:

```ocaml
let (_, select) = [%gensqlite dbh "select count(*) as <:count from users"] in
let print_res = function x::_ -> Printf.printf "count: %d\n" x | [] -> () in
print_res (select ())
```

In addition to the use of the aggregate `count`, here the output row `x` can be
used on its own, since single column outputs are primitive values.

#### Typing

SQLite is dynamically typed, and we can use that to our advantage. Recall that
the `created` field in the users table was defined as an integer (defaulting to
the current timestamp), yet value returned by SQLite during a query is actually
a string!

```
sqlite> select created from users;
2015-08-12 05:38:39
```

Hence the use of `strftime` in the `select` statement to convert the default
human-readable representation to a numeric value. However, the returned
representation is still a string. For situations like this, gensqlite attempts
to convert the returned value to the requested value. Here is another example of
runtime conversion:

```ocaml
let (_, select) = [%gensqlite dbh "select <@rowid from users where name = >:name"]
let () = insert ~username:"1001" ()
let res = select ~name:1001 ()
let print_res = function (id::_) -> Printf.printf "id: %s\n" id | [] -> ()
let () = print_res res
```

In this example, `select` was defined to return `rowid` (stored as an integer in
SQLite) as a string, while being parameterized by `name` as an integer (stored as a string in SQLite).

`gensqlite` will attempt to convert the output the best it can. Some output functions may raise a `Failure` on conversion (eg, `int_of_string`), but those are caught
and a default value returned instead. Defaults are also returned if the returned SQLite data is `NONE` or `NULL`. (Whether a default-based approach is better than a Result or Option is up for debate...) For strings, the default value is the empty string, while for numerics it is the type-equivalent value -1.

Inputs are obviously type-safe from OCaml, and SQLite internally does any
conversion it needs to match on inputs.

### Shortcomings and Future Work
--------------------------------

#### Records

Would have been nice to return records, rather
than tuples, but anonymous records don't exist in OCaml, and inserting record
declarations into the generated AST would take more work. Patches welcome!

For another OCaml-SQLite preprocessor that works on records, [orm](https://github.com/mirage/orm)
implements an ORM by associating create-read-update-delete (CRUD) operations to OCaml
records. This is a nice option to keep query manipulation in pure OCaml, and avoids the tedious boillerplate of writing CRUD operations manually.

#### Sigils

There is no way to escape sigil sequences at the moment (eg, `>@` or `<:`).
Hopefully such character sequences will be rare enough in practice. The
choice to use sigils to mark variables is a tradeoff between readability (printf-style specifiers would be hard to read adjoining a variable name), and in the use of regexps as
a poor man's lexer. In fact, proper lexing is probably needed before any
further extensions to the psuedo-SQL syntax. For a library with a sensible
syntax for input and output vriables, try
[ocaml-sqlexpr](https://github.com/mfp/ocaml-sqlexpr).



#### Stepping

Stepping, or streaming the result set is not supported -- the entire result set is
accumulated and returned at once, which may be problematic for large queries.
Perhaps a per-row callback could be added to the query function with an option
for `gensqlite` to disable accumulating and returning rows.

The callback approach is used to good effect by
[ocaml-sqlexpr](https://github.com/mfp/ocaml-sqlexpr), which also has a lot of
other nice features, many of which cover shortcomings of this implementation:
nicer SQL syntax, automatic finalization, concurrency ... (nb: actually, had I
known about ocaml-sqlexpr earlier, I probably wouldn't have written this library)

#### Statement Finalization

Note that all prepared statements must be finalized before the database handle
can be closed. Right now each statement needs to be manually
finalized; it is not possible to factor out ``gensqlite`` calls into a reusable
function that collects returned statements and queries, since the ``gensqlite``
query must be a string literal. For a very nice library that automatically
finalizes statements, try [ocaml-sqlexpr](https://github.com/mfp/ocaml-sqlexpr).

#### Floats, Nativeint

Not currently supported, should be pretty easy to add in if anyone needs it.

#### Wildcard Selection
Selections with wildcards do not really work; a "select * from table" would not
return any results. However, "select <:* from table" works, but only
returns the first column of the table due to the way output is extracted. Even
Even to make this work as expected, typing the returned tuple correctly would require schema
introspection at compile-time, akin to
[PGOCaml](https://github.com/darioteixeira/pgocaml/). For some insight into how
the `gensqlite` preprocessor works, pass the `-dsource` argument to `ocamlc` to
view the post-processed OCaml source code.


While gensqlite isn't trying to be the end-be-all of SQLite for OCaml,
hopefully it covers most of the common use cases nicely.
