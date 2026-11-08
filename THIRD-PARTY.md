# Third-party software

Cybersec Terminal's own code is MIT-licensed (see `LICENSE`). It is built with, and bundles, the following.

## Godot Engine (in every build)

The game runs on the Godot Engine, which is inside every downloadable build and the web version.
https://godotengine.org/

```
Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Godot itself includes further third-party libraries (for example FreeType and others), each with its own licence.
They are listed in Godot's `COPYRIGHT.txt` (https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt) and
at https://godotengine.org/license/.

## DejaVu Sans Mono (in every build)

The terminal font, `assets/fonts/DejaVuSansMono*.ttf`. Free to use and redistribute under the Bitstream Vera
and Arev licences. The full text is in `assets/fonts/DEJAVU-LICENSE.txt`.
https://dejavu-fonts.github.io/

## GUT, the Godot Unit Test framework (development only)

`addons/gut/`, MIT licence, Copyright (c) 2018 Tom "Butch" Wesley. Its licence is `addons/gut/LICENSE.md`.
It runs the tests and is **not** included in the game builds.
https://github.com/bitwes/Gut
