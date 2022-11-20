# Splines Renderer

This app is based on the dynamyc lines renderer - the MetalBuilder building block that renders strokes in the form of interpolating splines.
The splines connect the points that you pass in a buffer which element type is conforming to `MetalBuilderPointProtocol`.
This means that with MetalBuilder you may leverage the features of Swift language with Metal objects.

The rendering pipline uses indexed primitives and has compute shaders that are dispatched in two phases:

- calculate vertex indices and count them with an atomic counter (this is the first dispatch)
- copy index count to a variable to pass to the render encoder
- calculate spline segments (this is the second dispatch)
- calculate verties of the stroke sides
- render the indexed mesh

You may pass a FragmentShader as a parameter of the LinesRenderer to fully control the appearence of the splines.

