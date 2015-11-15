PROGS=ppx_gensqlite sample.byte sample.native test
all:  $(PROGS)

CC=ocamlfind ocamlc
CC_native=ocamlfind ocamlopt

PKGS = compiler-libs.common,ppx_tools.metaquot,re.pcre

ppx_gensqlite: q.ml ppx_gensqlite.ml
	$(CC) -package $(PKGS) -linkpkg -o $@ $^

gensqlite.%: gensqlite_tools.ml
	$(CC) -package sqlite3 $(LIB_CFLAGS) -o $@ $^

test: gensqlite.cma q.ml test.ml
	$(CC) -package re.pcre,oUnit,sqlite3 -ppx "./ppx_gensqlite" -o $@ -linkpkg $^

BACKENDS=native byte
LIB_CFLAGS=-a

%.native: CC:=$(CC_native)
%.cmxa: CC:=$(CC_native)
%.cmxs: CC:=$(CC_native)
%.cmxs: LIB_CFLAGS=-shared

native_LIB=cmxa
byte_LIB=cma

SAMPLES = $(BACKENDS:%=sample.%)

gensqlite:=gensqlite.$$($$*_LIB)

.SECONDEXPANSION:
$(SAMPLES): sample.% : $(gensqlite) sample.ml
	$(CC) -package sqlite3 -ppx "./ppx_gensqlite" -linkpkg -o $@ $^

lib: ppx_gensqlite gensqlite.cmxa gensqlite.cma gensqlite.cmxs

install: lib
	ocamlfind install gensqlite META LICENSE gensqlite.* gensqlite_tools.cmi
	cp ppx_gensqlite $(shell dirname `which ocamlfind`)

uninstall:
	ocamlfind remove gensqlite
	rm $(shell dirname `which ocamlfind`)/ppx_gensqlite

clean:
	rm -f *.cm[ioxa] *.cmx[as] *.o *.a *.cache $(PROGS)
