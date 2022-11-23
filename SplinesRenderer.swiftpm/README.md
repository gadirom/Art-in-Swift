# Splines Renderer

This app is based on the dynamyc splines renderer - the [MetalBuilder](https://github.com/gadirom/MetalBuilder) building block that renders strokes in the form of interpolating curves.
The splines connect the points passed in a buffer with element type conforming to `MetalBuilderPointProtocol`.
This means that with MetalBuilder you may leverage the features of Swift language for Metal objects.

The rendering pipline uses indexed primitives and has compute shaders that are dispatched in two phases:

* First dispatch:
- calculate vertex indices and count them with an atomic counter
- copy the index count to a variable to pass to the render encoder

* Second dispatch:
- calculate spline segments
- calculate vertices of the stroke sides
- render the indexed mesh

For full control over the appearance of the mesh you pass FragmentShader as a parameter to SplinesRenderer.
More documentation on how to use this block is in the code.

To run on iPad download the whole repository [Art-in-Swift](https://github.com/gadirom/Art-in-Swift) (Code->Download ZIP), run Files and unzip, then open this package (SplinesRenderer).

