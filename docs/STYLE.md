# Interface design

The app uses literal black surfaces, square window geometry, square controls, and thin functional outlines. Avoid rounded cards, beveled buttons, bottom highlights, and dimensional keycap shadows. Inter provides interface typography. Flexoki-derived blue marks selection and orange marks Apply; keyboard color choices are a separate palette.

The keyboard preview places radial RGB light pools below flat translucent black key faces at 82% opacity. Crisp neutral borders and static legends are drawn above the light field. A wider layout and bounded legends keep Pause, Mute, and other long labels inside their keys. Auxiliary strips sit at the case edges; the bar sits above the arrow cluster.

`LightingColorSwatch.value` holds device RGB. `.face` holds the shared presentation color. Standard swatches select full-scale red, green, blue, yellow, magenta, cyan, and white. Their display colors use softened hues, with HSV saturation raised 30% from the initial softened palette. Swatches, the selected-color chip, preset chips, keyboard glow, and colored outlines use the same mapping. Animated and custom hues interpolate through that palette while preserving intensity down to black. Hex text and the system color picker's underlying value remain device RGB.

This separation prevents a pastel button from accidentally sending a pale RGB mixture to the LEDs. It also makes the selected chip and preview agree with the buttons. Display mapping must not mutate settings, saved presets, or protocol payloads.

Colored outlines fade their opacity over the persistent gray edge. Do not paint an opaque RGB stroke that darkens toward black: it hides the neutral border. The radial light field is isolated in its own Canvas layer before crisp edges so filtering or blending cannot alter them. Effects remain buttons in a four-column layout.
