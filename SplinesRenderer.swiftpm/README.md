# Splines Renderer

(This app uses MetalBuilder's main branch and therefore will crash Swift Playgrounds. I will post an updated version as soon as the new version of MetalBuilder released)

This app is based on the dynamyc lines renderer - the MetalBuilder building block that renders strokes in the form of interpolating splines.
The splines connect the points that you pass in a buffer which element type is conforming to `MetalBuilderPointProtocol`.
This means that with MetalBuilder you may leverage the features of Swift language for Metal objects.

The rendering pipline uses indexed primitives and has compute shaders that are dispatched in two phases:

- calculate vertex indices and count them with an atomic counter (this is the first dispatch)
- copy index count to a variable to pass to the render encoder
- calculate spline segments (this is the second dispatch)
- calculate vertices of the stroke sides
- render the indexed mesh

For a full control over the appearance of the mesh you may pass a FragmentShader as a parameter to the LinesRenderer.
More documentation on how to use this block is in the code.

