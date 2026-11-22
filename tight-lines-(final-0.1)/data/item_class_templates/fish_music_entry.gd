class_name FishMusicEntry
extends Resource
## One "this fish plays this song" row for FishingManager's Fish Music list.
## Save this file as res://data/item_class_templates/fish_music_entry.gd

## Drag the fish's .tres record here (from res://data/fish/).
@export var fish: FishData
## The song played while this fish is on the line.
@export var music: AudioStream
## Volume for this song only. Lower it if this track is louder than the others.
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var volume_db := 0.0
