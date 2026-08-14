# Flutter AI rules — Code generation, testing, theming and assets

Code generation, the testing guidance, and the visual-design, theming and asset rules.

_Verbatim from [flutter/flutter docs/rules/rules.md](https://github.com/flutter/flutter/blob/main/docs/rules/rules.md), split across four files only to keep each under the repo's 250-line
cap. Re-fetch periodically to stay current; do not hand-edit._

* **Build Runner:** If the project uses code generation, ensure that
  `build_runner` is listed as a dev dependency in `pubspec.yaml`.
* **Code Generation Tasks:** Use `build_runner` for all code generation tasks,
  such as for `json_serializable`.
* **Running Build Runner:** After modifying files that require code generation,
  run the build command:

  ```shell
  dart run build_runner build --delete-conflicting-outputs
  ```

### Testing
* **Running Tests:** To run tests, use the `run_tests` tool if it is available,
  otherwise use `flutter test`.
* **Unit Tests:** Use `package:test` for unit tests.
* **Widget Tests:** Use `package:flutter_test` for widget tests.
* **Integration Tests:** Use `package:integration_test` for integration tests.
* **Assertions:** Prefer using `package:checks` for more expressive and readable
  assertions over the default `matchers`.

#### Testing Best practices
* **Convention:** Follow the Arrange-Act-Assert (or Given-When-Then) pattern.
* **Unit Tests:** Write unit tests for domain logic, data layer, and state
  management.
* **Widget Tests:** Write widget tests for UI components.
* **Integration Tests:** For broader application validation, use integration
  tests to verify end-to-end user flows.
* **integration_test package:** Use the `integration_test` package from the
  Flutter SDK for integration tests. Add it as a `dev_dependency` in
  `pubspec.yaml` by specifying `sdk: flutter`.
* **Mocks:** Prefer fakes or stubs over mocks. If mocks are absolutely
  necessary, use `mockito` or `mocktail` to create mocks for dependencies. While
  code generation is common for state management (e.g., with `freezed`), try to
  avoid it for mocks.
* **Coverage:** Aim for high test coverage.

### Visual Design & Theming
* **UI Design:** Build beautiful and intuitive user interfaces that follow
  modern design guidelines.
* **Responsiveness:** Ensure the app is mobile responsive and adapts to
  different screen sizes, working perfectly on mobile and web.
* **Navigation:** If there are multiple pages for the user to interact with,
  provide an intuitive and easy navigation bar or controls.
* **Typography:** Stress and emphasize font sizes to ease understanding, e.g.,
  hero text, section headlines, list headlines, keywords in paragraphs.
* **Background:** Keep backgrounds flat and simple — no noise texture or
  gradients. Follow the `unified-design-system` skill (safe-design-rules
  rule 17: simple-on-complex); let content and typography carry visual
  interest instead of background texture.
* **Shadows:** Follow the `unified-design-system` skill's shadow policy: no
  shadows at all in dark UI (differentiate elevation with lighter surface
  fills, not shadows); in light UI, shadows are for floating/overlay
  elements only (menus, dialogs), never for inline cards, and never mixed
  with a border on the same surface.
* **Icons:** Incorporate icons to enhance the user’s understanding and the
  logical navigation of the app.
* **Interactive Elements:** Buttons/controls signal state via color and fill
  changes, not a "glow" shadow — one depth technique per surface, per
  `unified-design-system`.

#### Theming
* **Centralized Theme:** Define a centralized `ThemeData` object to ensure a
  consistent application-wide style.
* **Light and Dark Themes:** Implement support for both light and dark themes,
  ideal for a user-facing theme toggle (`ThemeMode.light`, `ThemeMode.dark`,
  `ThemeMode.system`).
* **Color Scheme Generation:** Do NOT use `ColorScheme.fromSeed` for this
  app's palette — it can't reproduce hand-picked values exactly. Build
  `ThemeData` from explicit `ColorScheme.dark(...)`/`.light(...)` using the
  frozen, identical-everywhere tokens in the `unified-design-system` skill
  (`~/.claude/skills/unified-design-system/references/tokens.md`).

  ```dart
  final ThemeData lightTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: Brightness.light,
    ),
    // ... other theme properties
  );
  ```
* **Color Palette:** Include a wide range of color concentrations and hues in
  the palette to create a vibrant and energetic look and feel.
* **Component Themes:** Use specific theme properties (e.g., `appBarTheme`,
  `elevatedButtonTheme`) to customize the appearance of individual Material
  components.
* **Custom Fonts:** For custom fonts, use the `google_fonts` package. Define a
  `TextTheme` to apply fonts consistently.

  ```dart
  // 1. Add the dependency
  // flutter pub add google_fonts

  // 2. Define a TextTheme with a custom font
  final TextTheme appTextTheme = TextTheme(
    displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
    titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
    bodyMedium: GoogleFonts.openSans(fontSize: 14),
  );
  ```

#### Assets and Images
* **Image Guidelines:** If images are needed, make them relevant and meaningful,
  with appropriate size, layout, and licensing (e.g., freely available). Provide
  placeholder images if real ones are not available.
* **Asset Declaration:** Declare all asset paths in your `pubspec.yaml` file.

    ```yaml
    flutter:
      uses-material-design: true
      assets:
        - assets/images/
    ```

* **Local Images:** Use `Image.asset` for local images from your asset
  bundle.

    ```dart
    Image.asset('assets/images/placeholder.png')
    ```
* **Network images:** Use NetworkImage for images loaded from the network.
* **Cached images:** For cached images, use NetworkImage a package like
  `cached_network_image`.
* **Custom Icons:** Use `ImageIcon` to display an icon from an `ImageProvider`,
  useful for custom icons not in the `Icons` class.
* **Network Images:** Use `Image.network` to display images from a URL, and
  always include `loadingBuilder` and `errorBuilder` for a better user
  experience.

  ```dart
  // When using network images, always provide an errorBuilder.
  Image.network(
    'https://picsum.photos/200/300',
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return const Center(child: CircularProgressIndicator());
    },
    errorBuilder: (context, error, stackTrace) {
      return const Icon(Icons.error);
    },
  )
  ```

### UI Theming and Styling Code
