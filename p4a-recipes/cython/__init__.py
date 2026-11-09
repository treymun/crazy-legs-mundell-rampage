"""Cython 3 for pygame-ce builds on current p4a Python versions.

p4a's bundled recipe is Cython 0.29, which cannot run on the Python 3.14
hostpython used by the SDL2 bootstrap. pygame-ce 2.5.8 needs Cython 3, so this
local recipe installs a current release into the hostpython environment.
"""
from pythonforandroid.recipe import CompiledComponentsPythonRecipe


class CythonRecipe(CompiledComponentsPythonRecipe):
    version = "3.3.1"
    url = "https://github.com/cython/cython/archive/{version}.tar.gz"
    site_packages_name = "cython"
    depends = ["setuptools"]
    call_hostpython_via_targetpython = False
    install_in_hostpython = True


recipe = CythonRecipe()
