Craft only works with GHC 7.10.

# WIP

[![Join the chat at https://gitter.im/craft-hs/Lobby](https://badges.gitter.im/craft-hs/Lobby.svg)](https://gitter.im/craft-hs/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

***THIS PROJECT IS A WIP. DO NOT USE! BIG REFACTORS COMING SOON.***

# Getting Started

Get [stack](https://github.com/commercialhaskell/stack#how-to-install)

```
stack setup # only needs to be run your first time using stack
stack build
```

## Try me!

```
make
cd examples
vagrant up
./basic
```

# TODOs

See [TODOs.org](TODOs.org)

# Notes

## Remote execution

I plan to convert Craft to a Free Monad with a DSL of:

```haskell
execute        :: Env -> Command -> Args -> Craft (ExitCode, String, String)
execute_       :: Env -> Command -> Args -> Craft ()
readFile       :: AbsFilePath -> Craft ByteString
writeFile      :: AbsFilePath -> ByteString -> Craft ()
```

This won't allow for the complete freedom I had originally envisioned,
but it prevents enough catastrophic mistakes that I think it's worth it.
User will still be able to intersperse Craft runs inside an IO action,
so all the same functionality should still be possible.

Another possibility is: https://www.fpcomplete.com/user/agocorona/moving-haskell-processes-between-nodes-transient-effects-iv

## Different tools for different tasks, same configurations

One of the motivations for having multiple execution modes
is that some configurations require different execution patterns.

For example, it is not uncommon to *not* want to do a full reconfiguration
of the system on every change.
The reason being that some changes might be more fragile/risky than other.
This is what pushed based deployments are used for.
However, there might be configurations that should be run eagerly and regularly.

One example is using configuration management to manage users.

You definitely want to add and remove users during provisioning and deployment,
but you might also want users to be added and removed as soon as possible
without having to do a full-scale redeploy.

A way to accomplish this is to create a master/agent setup that runs regularly
and that only manages user configurations.
You then add *the same* user configurations to your master/agent setup _and_ your deployment script.
Thus you can have users added as soon as possible without having to
worry about a deployment accidentally interrupting service.

This is the kind of power you get when your configuration management is a library!


## Templates

I decided it's better whenever possible to use proper types,
renderers (e.g. ToJSON, ToYAML, printIni, etc),
and text buildlers (e.g. blaze-builder)
instead of templates.

I've also included a QuasiQuoter `[multiline| |]` for multiline strings
and `[raw_f|path/to/file|]` for embedding text files
(paths a relative to the build directory).

However, it might still be helpful to use have a general purpose templating library
just for the sake of being ,
but I haven't decided which one.
I'm open to suggestions.

## GHC Extensions

The following GHC extensions are enabled globally for this project:

 * QuasiQuotes
 * RecordWildCards
 * LambdaCase
 * BangPatterns

## Regex

Regular expressions should be avoided because they are cryptic and error-prone.

Parser combinators are more precise, composable, and readable, so they should be used instead.

Use `parseExec`.


# Module Wishlist

 * aws
 * systemd-nspawn
 * lxc
 * docker
 * guix
 * nix

# Ideas

 * [Prevent Resource Conflicts at Compile-Time](http://stackoverflow.com/a/26031509)
