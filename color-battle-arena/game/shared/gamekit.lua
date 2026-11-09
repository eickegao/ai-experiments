-- shared/gamekit.lua
-- Game Center integration for iOS
-- Requires: extension-gamekit
-- Dependency: https://github.com/animonger/extension-gamekit/archive/master.zip

local M = {}

M._authenticated = false
M._player_id = nil
M._on_authenticated = nil

function M.init(on_authenticated)
    local sysinfo = sys.get_sys_info()

    -- Only use Game Center on iOS
    if sysinfo.system_name ~= "iPhone OS" then
        return
    end

    -- Check if gamekit extension is available
    if not gamekit then
        print("GameKit extension not available - add dependency to game.project")
        return
    end

    M._on_authenticated = on_authenticated

    -- Authenticate with Game Center
    gamekit.gc_signin(function(self, event)
        print("Game Center event: " .. tostring(event.type))
        if event.type == "authenticated" then
            M._authenticated = true
            M._player_id = event.localPlayerID
            print("Game Center authenticated: " .. tostring(M._player_id))
            print("Game Center alias: " .. tostring(event.localPlayerAlias))
            if M._on_authenticated then
                M._on_authenticated(M._player_id)
            end
        elseif event.type == "error" then
            print("Game Center auth failed: " .. tostring(event.errorCode) .. " " .. tostring(event.description))
        elseif event.type == "showSignInUI" then
            -- 本机未登录 GC：弹系统登录界面（每次 init 只弹一次，防循环）
            if not M._signin_presented then
                M._signin_presented = true
                print("Game Center: presenting sign-in UI")
                gamekit.gc_show_signin("UI")
            end
        end
    end)
end

function M.is_authenticated()
    return M._authenticated
end

function M.get_player_id()
    return M._player_id
end

-- 扩展是否可用（iOS 且带 extension-gamekit 的构建）
function M.available()
    return gamekit ~= nil and sys.get_sys_info().system_name == "iPhone OS"
end

-- 提交排行榜分数；未认证/无扩展时静默丢弃
-- leaderboard_id 须与 App Store Connect 里配置的 ID 一致
function M.submit_score(leaderboard_id, value)
    if not M._authenticated or not gamekit then return end
    gamekit.gc_send("score", {
        leaderboardID = leaderboard_id,
        value = value,
        callback = function(_, event)
            if event.type == "error" then
                print("GC submit_score failed: " .. tostring(event.description))
            end
        end,
    })
end

-- 弹出系统排行榜界面；未认证时改为重试登录（允许再次弹登录 UI）
function M.show_leaderboard(leaderboard_id)
    if not gamekit then return end
    if not M._authenticated then
        M._signin_presented = false
        M.init(M._on_authenticated)
        return
    end
    gamekit.gc_show("leaderboardsUI", {
        leaderboardID = leaderboard_id,
        timeScope = "AllTime",
    })
end

return M
