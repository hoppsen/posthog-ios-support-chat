fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios check_translations

```sh
[bundle exec] fastlane ios check_translations
```

Check for missing translations

#### Example:

```
bundle exec fastlane check_translations
```

#### Options:

 * **`languages`**: Comma-separated list of language codes to check. Defaults to Xcode project languages.

### ios translate

```sh
[bundle exec] fastlane ios translate
```

Translates missing strings using ChatGPT

#### Example:

```
bundle exec fastlane translate
```

#### Options:

 * **`languages`**: Comma-separated list of language codes to translate to. Defaults to project languages.

 * **`filter_translated`**: If true, it filters out all translated strings before sending it off to ChatGPT. Defaults to true.

 * **`filter_reference_languages`**: Comma-separated list of language codes to include in the reference. Defaults to `en, de, sv`.

 * **`file`**: Path to specific .xcstrings file to translate. If not specified, processes all .xcstrings files.

### ios translate_batch

```sh
[bundle exec] fastlane ios translate_batch
```

Translates missing strings using ChatGPT in batches of 4 languages

#### Example:

```
bundle exec fastlane translate_batch languages:fr,es,it,de,nl,pt,ja,ko
```

#### Options:

 * **`languages`**: Comma-separated list of language codes to translate to (will be processed in batches). Defaults to project languages.

 * **`filter_translated`**: If true, it filters out all translated strings before sending it off to ChatGPT. Defaults to true.

 * **`filter_reference_languages`**: Comma-separated list of language codes to include in the reference. Defaults to `en, de, sv`.

 * **`file`**: Path to specific .xcstrings file to translate. If not specified, processes all .xcstrings files.

 * **`batch_size`**: Number of languages to process in each batch. Defaults to 3.

### ios remove_language

```sh
[bundle exec] fastlane ios remove_language
```

Removes specified languages from all xcstrings files

#### Example:

```
bundle exec fastlane remove_language languages:fr,es,it
```

#### Options:

 * **`languages`**: Comma-separated list of language codes to remove (required).

 * **`file`**: Path to specific .xcstrings file to process. If not specified, processes all .xcstrings files.

### ios setup

```sh
[bundle exec] fastlane ios setup
```

Installs the tracked git hooks (pre-commit lint/format)

### ios lint

```sh
[bundle exec] fastlane ios lint
```

Runs SwiftLint

### ios format

```sh
[bundle exec] fastlane ios format
```

Runs SwiftFormat

 * **`lint_only`**: Returns an error instead of reformatting. Defaults to false.

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
