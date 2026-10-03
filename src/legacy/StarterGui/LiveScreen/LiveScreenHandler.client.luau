-- StarterGui/LiveScreen/LiveScreenHandler (LocalScript) — PENSIUN (ruangan WORLD, claude/Rencana_World.md §16).
-- Panel "Live Screen" buatan Studio (MainFrame di ScreenGui ini) sudah DIGABUNG ke panel "Layar panggung"
-- (StarterPlayerScripts/DjStageAdmin, tab "Live Screen"; Menu › Settings › ADMIN › "Layar panggung").
-- Remote & server tidak berubah (ReplicatedStorage.LiveSystem, LiveScreenServer). Skrip ini hanya mematikan panel
-- lama supaya tidak muncul; UI Studio-nya boleh dihapus kapan saja (lalu hapus juga node "LiveScreen" di
-- default.project.json).
script.Parent.Enabled = false
