# Aetheria Development Notes

## Text client (`dev_tools/text_client.py`)
The repository does not currently include a `dev_tools/text_client.py` entry point. If a text client is added later, place it under a new `dev_tools/` directory and document how to launch it (for example with `python dev_tools/text_client.py`).

## Server (`aetheria_server/server_main.py`)
Likewise, there is no `aetheria_server/server_main.py` in this repository. When the server component is introduced, include the script under an `aetheria_server/` package and provide start-up instructions (e.g., `python -m aetheria_server.server_main`).

## Godot project location
A Godot project is not part of the current repository layout. Add the project directory to the repo (commonly a top-level folder containing `project.godot`) when available and update this section with its exact path.

## Python dependencies
The existing Python modules use only the standard library with one exception: the Arcade client in `arcade_client/` requires the `arcade` package. All other modules rely solely on built-in modules such as `math`, `os`, `random`, and `dataclasses`.
