# Voiced Lines

Drop voice recordings here to have them play alongside dialogue text boxes.

## How to enable a voiced line
In any dialogue JSON, add `"voiced": true` to the line:

```json
{
  "speaker": "S-1GN",
  "text": "Oh hey! Wow, you actually stopped to read me—how polite!",
  "portrait": "S-1GN-uwu",
  "voiced": true
}
```

## Folder structure
```
voiced-lines/{scene-name}/{speaker}/{first-five-words}.ogg
```

- **scene-name** — the name of the scene's root node (e.g. `Movement_Demo_02_24_2026`)
- **speaker** — the line's `"speaker"` value exactly (e.g. `S-1GN`)
- **first-five-words** — first five words of the `"text"`, lowercased, punctuation stripped, joined with dashes

Example for the line above:
```
voiced-lines/Movement_Demo_02_24_2026/S-1GN/oh-hey-wow-you-actually.ogg
```

Supported formats, tried in this order: `.ogg`, `.wav`, `.mp3`.
If the file is missing, the text box still shows normally and a warning is printed.
