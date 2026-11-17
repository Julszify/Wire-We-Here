class_name PlayerCtx
extends RefCounted
## Alles, was zu einer Figur gehört (eigene oder Mitspieler): Arm, Tasche, getragene Rolle, Seilbahnfahrt,
## Kabelsauger, Aussehen. world.gd arbeitet über `_actor` immer mit einem solchen Kontext; der Host führt
## Absichten der Mitspieler damit „als dieser Spieler“ aus.

var id := 1
var name := ""
var node: Player
var arm_reel: ReelData
## Knäuel in der Tasche (in der Reihenfolge, in der sie hineinkamen)
var bag: Array[CoilItem] = []
var carried_reel: ReelData
var cranking_reel: ReelData
## Laufende Seilbahnfahrt (nur bei der eigenen Figur): { line, s, dir, v }
var ride: Dictionary = {}
var vacuum_reels: Array[ReelData] = []
## Figur will saugen (eigene: Eingabe; Mitspieler: aus ihrer Figuren-Nachricht)
var vacuum_want := false
var vacuum_active := false
## Aussehen der Figur (Platz -> Kosmetik-ID), nur Figur-Teile; der Rest gilt für alle
var looks: Dictionary = {}
var label: Label3D
