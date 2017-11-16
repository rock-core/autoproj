This is the main build configuration of an autoproj installation

See http://rock-robotics.org/stable/documentation/autoproj for detailed information about autoproj.

Assuming that this build configuration is on e.g. github at
https://github.com/myorg/buildconf, a workspace based on this build
configuration can be bootstrapped using:

```
wget http://rock-robotics.org/autoproj_bootstrap
ruby autoproj_bootstrap git https://github.com/myorg/buildconf
```

Once bootstrapped, the main build configuration is checked out in the
workspace's `autoproj/` folder.

## Day-to-day workflow

`aup` updates the current package (or, if within a directory, the packages
under that directory). Use `--all` to update the whole workspace.

`amake` build the current package (or, if within a directory, the packages
under that directory). Use `--all` to build the whole workspace.

`autoproj status` will show the difference between the local workspace and
the remote repositories

`autoproj show PACKAGE` will display the configuration of said package, which
includes whether that package is selected in the current workspace ("a.k.a.
will be updated and built") and the import information (where the package
will be downloaded from)

## Autoproj configuration structure

The main build configuration tells autoproj about:

- which extra configurations should be imported ("package sets") in the
  `package_sets` section of the `manifest`. Once loaded, these package
  sets are made available in the `remotes/` subfolder of this configuration.
- which packages / package sets should be built in the `layout` section of
  the `manifest`
- which local overrides should be applied on package import (e.g. allowing
  to change a package's import branch or URL) in `.yml` files located in
  the `overrides.d` folder.

Overall, autoproj does the following with its configuration:

- load package description by (1) importing the package sets listed in
  `manifest` and (2) loading the `.autobuild` files in the imported package sets.
  Imported package sets are made available in the `remotes/` folder of this
  directory.
- resolve the import information (which can be inspected with `autoproj show`)

## Using extra RubyGems in an autoproj workspace

One can add new gems to a workspace, without passing through autoproj's osdeps
system, by adding new `.gemfile` files to the workspace's
`autoproj/overrides.d/` folder. These files must follow
[Bundler](http://bundler.io) gemfile format

