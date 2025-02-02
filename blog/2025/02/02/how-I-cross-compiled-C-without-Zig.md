# How I cross compiled C without Zig

Zig is a modern language known for it's great C interoperability amongst other
features. One of the main reasons it can do this is because of
[`zig cc`](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html),
a clang frontend that comes with Zig. It is able to cross compile C code even
though you wouldn't normally be able to do it with just clang or gcc.

Anyone who tried to cross compile C likely just installed the packages for
cross compiling in their distro. While that method works, it's not really fun
and if your distro doesn't provide the necessary packages you're on your own.
So I wanted to explore how you could cross compile from scratch.

Note that I'm doing everything on x86-64 Linux and it likely won't work on other
systems.

## A basic hello world program

	// main.c
	#include <stdio.h>
	
	int
	main(void)
	{
		printf("Hello World!\n");
	}

Compiling this code natively is pretty easy.

	$ clang -o main main.c
	$ ./main
	Hello World!

Cross compiling also seems easy, clang provides a `-target` flag to specify a
target architecture. This is also the reason why I used clang instead of gcc.

	$ clang -target arm64 -o main main.c
	/usr/bin/ld: /tmp/main-5bfac4.o: Relocations in generic ELF (EM: 183)
	/usr/bin/ld: /tmp/main-5bfac4.o: Relocations in generic ELF (EM: 183)
	/usr/bin/ld: /tmp/main-5bfac4.o: error adding symbols: file in wrong format
	collect2: error: ld returned 1 exit status
	clang: error: linker (via gcc) command failed with exit code 1 (use -v to see invocation)

Unfortunately, this fails. And it fails specifically at the linking stage. We
could prove that by generating the object file and linking separately. Lets
also use `lld` the llvm linker instead of GNU `ld`.

	$ clang -target arm64 -c -o main.o main.c
	$ file main.o
	main.o: ELF 64-bit LSB relocatable, ARM aarch64, version 1 (SYSV), not stripped
	$ clang -fuse-ld=lld -target arm64 -o main main.o
	ld.lld: error: main.o is incompatible with elf64-x86-64
	collect2: error: ld returned 1 exit status
	clang: error: linker (via gcc) command failed with exit code 1 (use -v to see invocation)

We did generate arm64 object file but lld still tries to link it as x86-64
object file. Now you could go into the rabbit hole of why it doesn't work by
passing `-v` to the linker and so on but I'll spoil the answer here.

We can't link because we need a libc compiled for arm64, but the system only
has an x86-64 libc. Directly using `lld` also isn't possible because of this.

	$ ld.lld -o main main.o
	ld.lld: error: undefined symbol: printf
	>>> referenced by main.c
	>>>               main.o:(main)

Note that if you were to not use the libc or any of the [startup
routines](https://en.wikipedia.org/wiki/Crt0), then it is possible to cross
compile it by just telling clang to not link with those files.

## Cross compiling musl libc

Honestly, there's not much to say here. You just make musl with llvm programs
instead of GNU ones and tell it to cross compile to the target platform. Note
that I'm installing this to `$HOME/opt/arm64-cross` and will refer to that
directory throughout this article.

	$ export AR=llvm-ar RANLIB=llvm-ranlib STRIP=llvm-strip READELF=llvm-readelf CC='clang -target arm64 -fuse-ld=lld'
	$ ./configure --prefix="$HOME"/opt/arm64-cross/ --target=aarch64 --disable-shared
	$ make
	$ make install

Now lets like the program manually.

	$ ld.lld -o main main.o -L $HOME/opt/arm64-cross/lib/ -lc $HOME/opt/arm64-cross/lib/crt1.o
	ld.lld: error: undefined symbol: __eqtf2
	>>> referenced by frexpl.c
	>>>               frexpl.o:(frexpl) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a
	>>> referenced by vfprintf.c
	>>>               vfprintf.o:(fmt_fp) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a
	>>> referenced by vfprintf.c
	>>>               vfprintf.o:(fmt_fp) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a

	ld.lld: error: undefined symbol: __extenddftf2
	>>> referenced by frexpl.c
	>>>               frexpl.o:(frexpl) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a
	>>> referenced by vfprintf.c
	>>>               vfprintf.o:(pop_arg) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a
	>>> referenced by vfprintf.c
	>>>               vfprintf.o:(fmt_fp) in archive /home/shaqeel/opt/arm64-cross/lib/libc.a
	......

It outputs a lot of errors so I truncated it. It seem to refer to certain
symbols like `__eqtf2`. A quick google search shows that they're part of
libgcc.

The [libgcc website](https://gcc.gnu.org/onlinedocs/gccint/Libgcc.html)
describes what it is.
<blockquote cite="https://gcc.gnu.org/onlinedocs/gccint/Libgcc.html">
GCC provides a low-level runtime library, libgcc.a or libgcc\_s.so.1 on some
platforms. GCC generates calls to routines in this library automatically,
whenever it needs to perform some operation that is too complicated to emit
inline code for.
</blockquote>

So the compiler just inserts function calls in certain places and those
functioons are implemented in libgcc. As far as I understand, it's not possible
to disable this

Clang also has a similar thing called compiler-rt. This means we'll also have
to cross compile compiler-rt. Honestly, I haven't compiled it properly but I'll
show how I did it.

## Cross compiling compiler-rt

First, I took the compiler-rt source archive from
<https://github.com/llvm/llvm-project/releases/tag/llvmorg-19.1.7>
and extracted it.

	$ cd compiler-rt-19.1.7.src/lib/builtins
	$ clang -target arm64 -c *.c
	$ ar rcs libcompiler-rt.a *.o
	$ cp libcompiler-rt.a $HOME/opt/arm64-cross/lib/

Yes, clang did spit out errors, I just ignored it and went on. I'll also
mention that tcc has `libtcc1.a` which may work as well if you want a less
hacky solution. Tcc is also capable of cross compiling and linking,
unfortunately it can't compile musl libc.


And finally, the moment everyone was waiting for...

	$ ld.lld -o main main.o -L $HOME/opt/arm64-cross/lib/ -lc -lcompiler-rt $HOME/opt/arm64-cross/lib/crt1.o
	$ qemu-aarch64 ./main
	Hello World!

## Compiling programs with more dependencies

Unfortunately, following this process means you'll have to cross-compile every
library that a program depends on. On languages like Go, this is what happens.
Those languages have dependency managers that allow them to compile every
single dependency to the target architecture.

This is also the case with `zig cc`. It can't compile programs with extra
dependencies.

## Conclusion

We can replicate the functionality of `zig cc`, but it must be done in 2 steps.
`zig cc` is capable of automatically linking to the right architecture and I
haven't had any success replicating it with clang in 1 command. So it's not
possible to use it in the `CC` environment variable like with `zig cc`.

It is possible to write a wrapper around clang and lld that does that, but
that's what `zig cc` is alreaady doing. I guess it can be nice if you didn't
need another language, to cross compile C.

## Bonus: tcc

Building tcc:

	$ ./configure --prefix="$HOME"/opt/arm64-cross/ --enable-cross --enable-static
	$ make
	$ make install

And building the hello world program:

	$ $HOME/opt/arm64-cross/bin/arm64-tcc -static -nostdlib -I $HOME/opt/arm64-cross/include -L $HOME/opt/arm64-cross/lib/ -o main main.c -lc $HOME/opt/arm64-cross/lib/crt1.o $HOME/opt/arm64-cross/lib/tcc/arm64-libtcc1.a -lc
	$ qemu-aarch64 ./main
	Hello World!

Interestingly, tcc can do it in 1 command. But for some reason it needs `-lc`
twice and also it needs to use the arm64 musl headers. While clang seemingly
just worked while using the x86-64 headers. I'm guessing I just got lucky with
clang.
