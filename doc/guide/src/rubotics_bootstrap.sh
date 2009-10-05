#! /bin/sh

RUBOTICS_ROOT=$PWD
export GEM_HOME=$PWD/rubotics/gems
export PATH=$GEM_HOME/bin:$PATH
gem install rubotics

echo "export GEM_HOME=$PWD/rubotics/gems" >  $PWD/env.sh
echo "export PATH=$GEM_HOME/bin:$PATH"    >> $PWD/env.sh
echo
echo "add the following line to your .bashrc:"
echo "  source $PWD/env.sh"
echo
echo "this will properly set up the environment variables"
echo "so that you can use the rubotics installation"

