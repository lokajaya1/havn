# Laporan ekstraksi Tahap 1

Sumber: `/Users/lokajayaandala/Downloads/HAVN_backup_2026-09-26.rbxl` (md5 72be4e316260a5eaff4e4a49686c842b)

Total skrip: **448** · diekstrak ke `src/legacy/`: **109** · ditinggal di place: **339**

## Alasan ditinggal
| Jumlah | Alasan |
|---|---|
| 108 | Workspace: aset/map, Tahap 1 tidak dipetakan |
| 63 | nama '…' kembar dengan saudaranya di ReplicatedStorage |
| 58 | nama '…' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| 42 | berisi PackageLink '…' (bukan skrip) |
| 28 | di dalam ScreenGui '…' |
| 9 | di dalam Model '…' |
| 7 | berisi StringValue '…' (bukan skrip) |
| 7 | berisi IntValue '…' (bukan skrip) |
| 6 | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| 5 | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| 1 | berisi CurveAnimation '…' (bukan skrip) |
| 1 | di dalam ImageLabel '…' |
| 1 | ada anak bernama kembar di ReplicatedStorage/CarryReplic/CarryChoices/Dragging Carry |
| 1 | berisi Frame '…' (bukan skrip) |
| 1 | berisi Decal '…' (bukan skrip) |
| 1 | di dalam ImageButton '…' |

## Diekstrak
| Explorer | File | Disabled |
|---|---|---|
| ReplicatedStorage/AnimationCache/AnimationCacheManager | `src/legacy/ReplicatedStorage/AnimationCache/AnimationCacheManager.luau` |  |
| ReplicatedStorage/CarryReplic/CarryRemotes/CarryWeld | `src/legacy/ReplicatedStorage/CarryReplic/CarryRemotes/CarryWeld.luau` |  |
| ReplicatedStorage/Config/DanceConfig | `src/legacy/ReplicatedStorage/Config/DanceConfig.luau` |  |
| ReplicatedStorage/Config/DanceConfigHelper | `src/legacy/ReplicatedStorage/Config/DanceConfigHelper.luau` |  |
| ReplicatedStorage/CustomTween/TweenLibrary | `src/legacy/ReplicatedStorage/CustomTween/TweenLibrary.luau` |  |
| ReplicatedStorage/CustomTween/TweenManager | `src/legacy/ReplicatedStorage/CustomTween/TweenManager.luau` |  |
| ReplicatedStorage/CustomUIModules/AddFriendManager | `src/legacy/ReplicatedStorage/CustomUIModules/AddFriendManager.luau` |  |
| ReplicatedStorage/CustomUIModules/CarryManager | `src/legacy/ReplicatedStorage/CustomUIModules/CarryManager.luau` |  |
| ReplicatedStorage/CustomUIModules/CarryStateDetector | `src/legacy/ReplicatedStorage/CustomUIModules/CarryStateDetector.luau` |  |
| ReplicatedStorage/CustomUIModules/CarryUI | `src/legacy/ReplicatedStorage/CustomUIModules/CarryUI.luau` |  |
| ReplicatedStorage/CustomUIModules/Communityinfo | `src/legacy/ReplicatedStorage/CustomUIModules/Communityinfo.luau` |  |
| ReplicatedStorage/CustomUIModules/HideAvatarManager | `src/legacy/ReplicatedStorage/CustomUIModules/HideAvatarManager.luau` |  |
| ReplicatedStorage/CustomUIModules/MenuBinder | `src/legacy/ReplicatedStorage/CustomUIModules/MenuBinder.luau` |  |
| ReplicatedStorage/CustomUIModules/PrivateChatManager | `src/legacy/ReplicatedStorage/CustomUIModules/PrivateChatManager.luau` |  |
| ReplicatedStorage/CustomUIModules/Responsive | `src/legacy/ReplicatedStorage/CustomUIModules/Responsive.luau` |  |
| ReplicatedStorage/CustomUIModules/ShowAvatarModule | `src/legacy/ReplicatedStorage/CustomUIModules/ShowAvatarModule.luau` |  |
| ReplicatedStorage/CustomUIModules/StateManager | `src/legacy/ReplicatedStorage/CustomUIModules/StateManager.luau` |  |
| ReplicatedStorage/CustomUIModules/SyncManager | `src/legacy/ReplicatedStorage/CustomUIModules/SyncManager.luau` |  |
| ReplicatedStorage/CustomUIModules/UI/ButtonManager | `src/legacy/ReplicatedStorage/CustomUIModules/UI/ButtonManager.luau` |  |
| ReplicatedStorage/CustomUIModules/UI/MenuController | `src/legacy/ReplicatedStorage/CustomUIModules/UI/MenuController.luau` |  |
| ReplicatedStorage/CustomUIModules/UI/MenuCreator | `src/legacy/ReplicatedStorage/CustomUIModules/UI/MenuCreator.luau` |  |
| ReplicatedStorage/CustomUIModules/UI/UIAnimator | `src/legacy/ReplicatedStorage/CustomUIModules/UI/UIAnimator.luau` |  |
| ReplicatedStorage/CustomUIModules/UI/UIConstants | `src/legacy/ReplicatedStorage/CustomUIModules/UI/UIConstants.luau` |  |
| ReplicatedStorage/CustomUIModules/UIManager | `src/legacy/ReplicatedStorage/CustomUIModules/UIManager.luau` |  |
| ReplicatedStorage/CustomUIModules/ViewProfileManager | `src/legacy/ReplicatedStorage/CustomUIModules/ViewProfileManager.luau` |  |
| ReplicatedStorage/GameSettings | `src/legacy/ReplicatedStorage/GameSettings.luau` |  |
| ReplicatedStorage/Modules/AnimationWarmup | `src/legacy/ReplicatedStorage/Modules/AnimationWarmup.luau` |  |
| ReplicatedStorage/Modules/SmoothDanceHelper | `src/legacy/ReplicatedStorage/Modules/SmoothDanceHelper.luau` |  |
| ReplicatedStorage/Modules/SmoothDanceManager | `src/legacy/ReplicatedStorage/Modules/SmoothDanceManager.luau` |  |
| ReplicatedStorage/MusicShared | `src/legacy/ReplicatedStorage/MusicShared.luau` |  |
| ReplicatedStorage/ProfileService | `src/legacy/ReplicatedStorage/ProfileService.luau` |  |
| ReplicatedStorage/ShopConfig | `src/legacy/ReplicatedStorage/ShopConfig.luau` |  |
| ReplicatedStorage/TitleStyle | `src/legacy/ReplicatedStorage/TitleStyle.luau` |  |
| ServerScriptService/AG-MusicGlobal | `src/legacy/ServerScriptService/AG-MusicGlobal.server.luau` | ya |
| ServerScriptService/AnimationHandler | `src/legacy/ServerScriptService/AnimationHandler.server.luau` | ya |
| ServerScriptService/AnnouncementHandler | `src/legacy/ServerScriptService/AnnouncementHandler.server.luau` |  |
| ServerScriptService/AssetPermissionGran | `src/legacy/ServerScriptService/AssetPermissionGran.server.luau` | ya |
| ServerScriptService/CarrySystemHandler | `src/legacy/ServerScriptService/CarrySystemHandler.server.luau` |  |
| ServerScriptService/CommandServer | `src/legacy/ServerScriptService/CommandServer.server.luau` |  |
| ServerScriptService/Communityinfoservice | `src/legacy/ServerScriptService/Communityinfoservice.server.luau` |  |
| ServerScriptService/DonationMessageHandler | `src/legacy/ServerScriptService/DonationMessageHandler.server.luau` | ya |
| ServerScriptService/DonationServer | `src/legacy/ServerScriptService/DonationServer.server.luau` | ya |
| ServerScriptService/FavoritePrompt | `src/legacy/ServerScriptService/FavoritePrompt.server.luau` |  |
| ServerScriptService/FlyingbroomServer | `src/legacy/ServerScriptService/FlyingbroomServer.server.luau` |  |
| ServerScriptService/GlowStickServer | `src/legacy/ServerScriptService/GlowStickServer.server.luau` |  |
| ServerScriptService/HammerServer | `src/legacy/ServerScriptService/HammerServer.server.luau` |  |
| ServerScriptService/Likesystem | `src/legacy/ServerScriptService/Likesystem.server.luau` |  |
| ServerScriptService/LiveScreenServer | `src/legacy/ServerScriptService/LiveScreenServer.server.luau` |  |
| ServerScriptService/Misc/DanceHandler | `src/legacy/ServerScriptService/Misc/DanceHandler.server.luau` |  |
| ServerScriptService/Misc/SyncCommand | `src/legacy/ServerScriptService/Misc/SyncCommand.server.luau` |  |
| ServerScriptService/MusicServer | `src/legacy/ServerScriptService/MusicServer/init.server.luau` |  |
| ServerScriptService/MusicServer/Library | `src/legacy/ServerScriptService/MusicServer/Library.luau` |  |
| ServerScriptService/MusicServer/Playback | `src/legacy/ServerScriptService/MusicServer/Playback.luau` |  |
| ServerScriptService/Namailang | `src/legacy/ServerScriptService/Namailang.server.luau` |  |
| ServerScriptService/OverheadTag | `src/legacy/ServerScriptService/OverheadTag.server.luau` |  |
| ServerScriptService/PlayerCollisionManager | `src/legacy/ServerScriptService/PlayerCollisionManager.server.luau` |  |
| ServerScriptService/RagDollTag | `src/legacy/ServerScriptService/RagDollTag.server.luau` |  |
| ServerScriptService/RankConfig | `src/legacy/ServerScriptService/RankConfig.luau` |  |
| ServerScriptService/ReceiptHandler | `src/legacy/ServerScriptService/ReceiptHandler.luau` |  |
| ServerScriptService/RefreshCharacter | `src/legacy/ServerScriptService/RefreshCharacter.server.luau` | ya |
| ServerScriptService/RoleManagerServer | `src/legacy/ServerScriptService/RoleManagerServer.server.luau` |  |
| ServerScriptService/ScriptEmitter | `src/legacy/ServerScriptService/ScriptEmitter.server.luau` |  |
| ServerScriptService/ShopServer | `src/legacy/ServerScriptService/ShopServer.server.luau` |  |
| ServerScriptService/SyncGIFClones | `src/legacy/ServerScriptService/SyncGIFClones.server.luau` |  |
| ServerScriptService/TeamSystem | `src/legacy/ServerScriptService/TeamSystem.server.luau` |  |
| ServerScriptService/ToolGiver | `src/legacy/ServerScriptService/ToolGiver.server.luau` |  |
| ServerScriptService/Transferdonationdata | `src/legacy/ServerScriptService/Transferdonationdata.server.luau` | ya |
| ServerScriptService/UnifiedRankManager | `src/legacy/ServerScriptService/UnifiedRankManager.server.luau` |  |
| StarterGui/CommandPanel | `src/legacy/StarterGui/CommandPanel.client.luau` |  |
| StarterGui/DonationMessageClient | `src/legacy/StarterGui/DonationMessageClient.client.luau` | ya |
| StarterGui/DonationMessageNotification | `src/legacy/StarterGui/DonationMessageNotification.client.luau` | ya |
| StarterGui/Flyingbroomui | `src/legacy/StarterGui/Flyingbroomui.client.luau` |  |
| StarterGui/FreeCam | `src/legacy/StarterGui/FreeCam.client.luau` |  |
| StarterGui/GlowStickUI | `src/legacy/StarterGui/GlowStickUI.client.luau` |  |
| StarterGui/GraphicsClient | `src/legacy/StarterGui/GraphicsClient.client.luau` |  |
| StarterGui/InfoTopBar | `src/legacy/StarterGui/InfoTopBar.client.luau` |  |
| StarterGui/MoneyGunUI | `src/legacy/StarterGui/MoneyGunUI.client.luau` |  |
| StarterGui/PlayersClient | `src/legacy/StarterGui/PlayersClient.client.luau` |  |
| StarterGui/RoleManagerClient | `src/legacy/StarterGui/RoleManagerClient.client.luau` |  |
| StarterGui/SettingsClient | `src/legacy/StarterGui/SettingsClient.client.luau` |  |
| StarterGui/ShopClient | `src/legacy/StarterGui/ShopClient.client.luau` |  |
| StarterGui/WaterGunUI | `src/legacy/StarterGui/WaterGunUI.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/360 | `src/legacy/StarterPlayer/StarterPlayerScripts/360.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/AnnouncementClient | `src/legacy/StarterPlayer/StarterPlayerScripts/AnnouncementClient.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/AvatarContextMenu | `src/legacy/StarterPlayer/StarterPlayerScripts/AvatarContextMenu.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/ChatTags | `src/legacy/StarterPlayer/StarterPlayerScripts/ChatTags.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/ClientPreloader | `src/legacy/StarterPlayer/StarterPlayerScripts/ClientPreloader.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/CommunNFav | `src/legacy/StarterPlayer/StarterPlayerScripts/CommunNFav.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/CustomBackpackUI | `src/legacy/StarterPlayer/StarterPlayerScripts/CustomBackpackUI.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/DanceClient | `src/legacy/StarterPlayer/StarterPlayerScripts/DanceClient.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/DanceController | `src/legacy/StarterPlayer/StarterPlayerScripts/DanceController.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/DonationVFX | `src/legacy/StarterPlayer/StarterPlayerScripts/DonationVFX.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/EqualizerFrame_Dekstop | `src/legacy/StarterPlayer/StarterPlayerScripts/EqualizerFrame_Dekstop.luau` |  |
| StarterPlayer/StarterPlayerScripts/EqualizerFrame_Mobile | `src/legacy/StarterPlayer/StarterPlayerScripts/EqualizerFrame_Mobile.luau` |  |
| StarterPlayer/StarterPlayerScripts/InteractPlayer/InteractionLoad | `src/legacy/StarterPlayer/StarterPlayerScripts/InteractPlayer/InteractionLoad.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/LeaderboardClient | `src/legacy/StarterPlayer/StarterPlayerScripts/LeaderboardClient.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/Likeeffects | `src/legacy/StarterPlayer/StarterPlayerScripts/Likeeffects.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/ListQueue_Dekstop | `src/legacy/StarterPlayer/StarterPlayerScripts/ListQueue_Dekstop.luau` |  |
| StarterPlayer/StarterPlayerScripts/ListQueue_Mobile | `src/legacy/StarterPlayer/StarterPlayerScripts/ListQueue_Mobile.luau` |  |
| StarterPlayer/StarterPlayerScripts/MenuSystemInit | `src/legacy/StarterPlayer/StarterPlayerScripts/MenuSystemInit.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/Mirrorscript | `src/legacy/StarterPlayer/StarterPlayerScripts/Mirrorscript.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/MultiScreenController | `src/legacy/StarterPlayer/StarterPlayerScripts/MultiScreenController.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/MusicClient | `src/legacy/StarterPlayer/StarterPlayerScripts/MusicClient/init.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/MusicClient/Audio | `src/legacy/StarterPlayer/StarterPlayerScripts/MusicClient/Audio.luau` |  |
| StarterPlayer/StarterPlayerScripts/MusicClient/Lists | `src/legacy/StarterPlayer/StarterPlayerScripts/MusicClient/Lists.luau` |  |
| StarterPlayer/StarterPlayerScripts/MusicClient/UI | `src/legacy/StarterPlayer/StarterPlayerScripts/MusicClient/UI.luau` |  |
| StarterPlayer/StarterPlayerScripts/Musicprogressreporter | `src/legacy/StarterPlayer/StarterPlayerScripts/Musicprogressreporter.client.luau` | ya |
| StarterPlayer/StarterPlayerScripts/TitlePlate | `src/legacy/StarterPlayer/StarterPlayerScripts/TitlePlate.client.luau` |  |
| StarterPlayer/StarterPlayerScripts/sprintSystem | `src/legacy/StarterPlayer/StarterPlayerScripts/sprintSystem.client.luau` |  |

## Ditinggal di place
| Explorer | Alasan |
|---|---|
| ReplicatedStorage/AnnouncementUI/BG/Text/ignore me | di dalam ImageLabel 'ReplicatedStorage/AnnouncementUI/BG' |
| ReplicatedStorage/Assets/Animations/Dances/DanceAssets | berisi CurveAnimation 'Imported Animation Clip [CHANNELS]' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Bridal Carry | berisi StringValue 'FirstAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Couple Hug | berisi StringValue 'FirstAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Dragging Carry | ada anak bernama kembar di ReplicatedStorage/CarryReplic/CarryChoices/Dragging Carry |
| ReplicatedStorage/CarryReplic/CarryChoices/Fireman's Carry | berisi StringValue 'FirstAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Front Carry | berisi IntValue 'Carry Laki' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Gelut | berisi StringValue 'FirstAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Hug | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Kuli | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Nyeret | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/PiggyUpperBack | berisi StringValue 'SecondAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Piggyback | berisi StringValue 'FirstAnim' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Pundak | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Shoulder | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Side Carry | berisi StringValue 'Carrier' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryChoices/Tangan Satu | berisi IntValue 'Carry Perempuan' (bukan skrip) |
| ReplicatedStorage/CarryReplic/CarryRemotes/buttontemplate/Hover | di dalam ImageButton 'ReplicatedStorage/CarryReplic/CarryRemotes/buttontemplate' |
| ReplicatedStorage/Icon | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Attribute | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Attribute | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Attribute | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Caption | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Caption | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Caption | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Container | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Container | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Container | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Dropdown | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Dropdown | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Dropdown | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Indicator | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Indicator | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Indicator | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Menu | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Menu | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Menu | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Notice | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Notice | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Notice | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Selection | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Selection | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Selection | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Widget | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Widget | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Elements/Widget | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Gamepad | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Gamepad | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Gamepad | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Overflow | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Overflow | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Overflow | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Classic | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Classic | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Classic | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Default | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Default | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Features/Themes/Default | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/GoodSignal | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/GoodSignal | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/GoodSignal | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/Janitor | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/Janitor | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Packages/Janitor | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Reference | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Reference | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Reference | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Types | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Types | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Types | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Utility | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Utility | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/Utility | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/VERSION | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/VERSION | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/Icon/VERSION | nama 'Icon' kembar dengan saudaranya di ReplicatedStorage |
| ReplicatedStorage/R15 Character Animations/Animate | di dalam Model 'ReplicatedStorage/R15 Character Animations' |
| ReplicatedStorage/R15 Character Animations/Glass/LocalScript | di dalam Model 'ReplicatedStorage/R15 Character Animations' |
| ReplicatedStorage/R15 Shaker Animations/Animate | di dalam Model 'ReplicatedStorage/R15 Shaker Animations' |
| ReplicatedStorage/RagdollService | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Client | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Client/Components/ragdoll | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Client/renderCharacters | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Server | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Server/Components/Ragdoll | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Server/Components/RagdollOnHumanoidDied | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Server/Components/Ragdollable | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Classes/ragdoll | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Constants | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Client/ClientProcess | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Client/ClientProcess/Logger | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Client/Index | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Event | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Server/Index | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Server/ServerProcess | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Server/ServerProcess/Logger | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Signal | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Signal/Dedicated | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Type | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Assert | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Buffer | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Buffer/Dedicated | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Key | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Middleware | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/RateLimit | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Serdes | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/imezx_warp@1.0.12/warp/Index/Util/Spawn | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/Promise | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/Signal | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/Symbol | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/Trove | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/component | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/component/init.spec | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_component@2.4.8/component/wally | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_signal@2.0.1/signal | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_signal@2.0.1/signal/init.spec | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_signal@2.0.1/signal/wally | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_symbol@2.0.1/symbol | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_symbol@2.0.1/symbol/init.spec | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_symbol@2.0.1/symbol/wally | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_trove@1.4.0/trove | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_trove@1.4.0/trove/init.spec | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/_Index/sleitnick_trove@1.4.0/trove/wally | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/component | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/promise | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/trove | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Packages/warp | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Utils/assert | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Utils/cameraSpring | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Utils/character | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Utils/ragdollConstraints | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/Utils/spring | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/RagdollService/Shared/wally | nama 'init' punya arti khusus di Rojo (ReplicatedStorage/RagdollService/Shared/Packages/_Index/evaera_promise@4.0.0/promise/init.spec) |
| ReplicatedStorage/Topbar/Icon | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Attribute | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Caption | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Container | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Dropdown | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Indicator | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Menu | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Notice | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Selection | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Elements/Widget | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Features/Gamepad | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Features/Overflow | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Features/Themes | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Features/Themes/Classic | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Features/Themes/Default | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Packages/GoodSignal | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Packages/Janitor | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Reference | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/Utility | berisi PackageLink 'PackageLink' (bukan skrip) |
| ReplicatedStorage/Topbar/Icon/VERSION | berisi PackageLink 'PackageLink' (bukan skrip) |
| ServerScriptService/Adonis_Loader/Config/API | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/Adonis_Loader/Config/Plugins/Client-Example Plugin | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/Adonis_Loader/Config/Plugins/Server-Example Plugin | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/Adonis_Loader/Config/Settings | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/Adonis_Loader/Config/Themes/README | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/Adonis_Loader/Loader/Loader | di dalam Model 'ServerScriptService/Adonis_Loader' |
| ServerScriptService/StandAlone | berisi Frame 'Template' (bukan skrip) |
| ServerStorage/Flying Broom/LocalScript | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| ServerStorage/Money Gun/LocalScript | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| ServerStorage/Money Gun/Serverscript | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| ServerStorage/WaterGun/LocalScript | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| ServerStorage/WaterGun/Script | ServerStorage: aset/map, Tahap 1 tidak dipetakan |
| StarterGui/AG-OpenMusic | berisi Decal 'Dance Emoji' (bukan skrip) |
| StarterGui/CarrySelectGUI/LocalScript | di dalam ScreenGui 'StarterGui/CarrySelectGUI' |
| StarterGui/EventGUI/BlackHole | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/BlackHole/CameraShaker | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/BlackHole/CameraShaker/CameraShakeInstance | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/BlackHole/CameraShaker/CameraShakePresets | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShakeInstance | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShakePresets | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker/CameraShakeInstance | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker/CameraShakePresets | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker/CameraShaker | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker/CameraShaker/CameraShakeInstance | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Hammer/CameraShaker/CameraShaker/CameraShaker/CameraShakePresets | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Nuke | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Nuke/CameraShaker | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Nuke/CameraShaker/CameraShakeInstance | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Nuke/CameraShaker/CameraShakePresets | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/EventGUI/Nuke/Scripts/SpawnFireworks | di dalam ScreenGui 'StarterGui/EventGUI' |
| StarterGui/LiveScreen/AutoResize | di dalam ScreenGui 'StarterGui/LiveScreen' |
| StarterGui/LiveScreen/LiveScreenHandler | di dalam ScreenGui 'StarterGui/LiveScreen' |
| StarterGui/MenuUI/DynamicTools | di dalam ScreenGui 'StarterGui/MenuUI' |
| StarterGui/MenuUI/UltimateMenu | di dalam ScreenGui 'StarterGui/MenuUI' |
| StarterGui/StageParticleGUI/LocalScript | di dalam ScreenGui 'StarterGui/StageParticleGUI' |
| StarterGui/StageParticleGUI/ScriptEmitter | di dalam ScreenGui 'StarterGui/StageParticleGUI' |
| StarterGui/TextSignRequestUI/LocalScript | di dalam ScreenGui 'StarterGui/TextSignRequestUI' |
| StarterGui/TextSignRequestUI/TextSignRequestUI | di dalam ScreenGui 'StarterGui/TextSignRequestUI' |
| StarterPack/GlowStick/ServerScript | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPack/Sign/LocalScript | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPack/Sign/LocalScript/BGColor/Script | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPack/Sign/LocalScript/RemoteEvent/Script | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPack/Sign/LocalScript/SS/TextButton/LocalScript | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPack/Sign/LocalScript/TextColor/Script | StarterPack: aset/map, Tahap 1 tidak dipetakan |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Attribute | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Caption | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Container | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Dropdown | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Indicator | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Menu | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Notice | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Selection | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Elements/Widget | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Features/Gamepad | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Features/Overflow | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Features/Themes | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Features/Themes/Classic | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Features/Themes/Default | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Packages/GoodSignal | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Packages/Janitor | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Reference | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Types | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/Utility | berisi PackageLink 'PackageLink' (bukan skrip) |
| StarterPlayer/StarterPlayerScripts/PlayerHideShow/Icon/VERSION | berisi PackageLink 'PackageLink' (bukan skrip) |
| Workspace/(Animated) Realistic tree/Part/READ ME | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/(Animated) Realistic tree/Part/READ ME | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/(Animated) Realistic tree/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/(Animated) Realistic tree/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/360Cam/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/READ ME | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/READ ME | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/READ ME | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Animated Tree/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Basic Modern Drum light/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Basic Modern Drum light/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Basic Modern Drum light/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Switch/Light symbol/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Switch/Light symbol/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Switch/Light symbol/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Switch/Light symbol/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Beach kiosh/Beach kiosk/Light Test/Model/Switch/Light symbol/Union/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/A/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/B/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/BaseCDJ/DecorationButtons/USBButtons/USBLed/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/BaseCDJ/DecorationButtons/USBButtons/USBLed/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/BaseCDJ/DecorationButtons/USBButtons/USBLed/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/BaseCDJ/DecorationButtons/USBButtons/USBLed/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue1/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue2/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue3/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue4/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue5/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue6/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue7/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Cue8/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/DELAY/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/ECHO/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/EffectToggle/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/EffectToggle/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/FILTER/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Four/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/GATE/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Interact/Animate/BaseLED/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Interact/Animate/BaseLED/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Interact/Animate/BaseLED/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Interact/Animate/BaseLED/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/M/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/MIC/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/MIDI/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/MIX/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/MultiTapDelay/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/One/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/PHASER/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/REVERB/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/REVROLL/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/ROLL/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/SENDRETURN/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/SLIPROLL/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/TAP/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/TAP/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/TRANS/loop | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Three/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/dj/Two/Interaction | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/stage/Beam/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/stage/EntranceScreenC/VJScript | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/stage/StageScreens/EntranceScreen/VJScript | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/DJ STAGE/stage/StageScreens/EntranceScreen/VJScript | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Model/Angel Lucy Statue II/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/TimePlayedLeaderboard/First Place Avatar/PlayAnimationInRig | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/TimePlayedLeaderboard/Settings | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/TimePlayedLeaderboard/TimePlayedClass | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/Vending Machine/WAFFLEB/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Model/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/flower fountain/Fountain/Part/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/streetbuild/crashed car/Body/Racing Seat/Weld 2.1 | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/streetbuild/crashed car/Body/Racing Seat/Weld 2.1 | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/streetbuild/crashed car/Body/Rear Neon/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/streetbuild/crashed car/Body/whole int ok/Dials/Neon Details/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
| Workspace/streetbuild/crashed car/Body/whole int ok/Dials/Neon Dials/Script | Workspace: aset/map, Tahap 1 tidak dipetakan |
