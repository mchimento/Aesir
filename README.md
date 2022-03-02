# Aesir
Prototype version of a tool to infer global trace conditions from partial local proofs. In order to compile Aesir you must have installed a Haskell compiler: ghc-8.10.7 or later recommended.

At the time of compiling, you can let cabal doing it for you as follows:

cabal configure
cabal build

Note that you will probably have to install the following packages:

language-java >= 0.2.7

HaXml >= 1.25.3

split >= 0.2.2

lens >= 5.1

If that is the case, then you can use the standard Cabal method of installation:

cabal update
cabal install haxml

For older compilers, use:

./configure [--prefix=...] [--buildwith=...]
make
make install

Note that the KeY API (i.e. folder KeY) should be place in the same place as the Aesir binary in order to run Aesir.
