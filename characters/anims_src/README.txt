Original Mixamo clips (Standard_Run.fbx, Jump.fbx, Dying.fbx). The game does NOT use these files directly.
They were fitted to the Valery skeleton once and saved as ../anims/valery_anims.res (clips: idle, run, jump, die).
This folder has a .gdignore file, so Godot does not import it and the APK stays small.
To make the clips again (new / more Mixamo files): delete .gdignore, open the project in Godot, edit tools/bake_anims.gd
(list OUT / SRC at the top) and run it:  godot --headless --script tools/bake_anims.gd
