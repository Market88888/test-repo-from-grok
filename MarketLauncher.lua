-- encoding: UTF-8
script_name("Market Launcher")
script_description("Downloader & Updater")
script_author("Shinik_Pupckin")
script_version("1.1")

local effil = require('effil')
require('lib.moonloader')
local imgui = require('mimgui')

local function u8(s)
    if s == nil then return '' end
    if type(s) ~= 'string' then return tostring(s) end
    return s
end

local function path_join(base, file)
    return (base:gsub('\\', '/') .. '/' .. file):gsub('//+', '/')
end

local BASE_DIR = getWorkingDirectory():gsub('\\', '/')

local MH = {
    key          = 'mh',
    title        = 'Market Helper',
    github_user  = 'ShiNiK-Dev',
    github_repo  = 'MarketHelper',
    file         = 'MarketHelper.lua',
    author       = 'Shinik_Pupckin',
    tg           = 'https://t.me/shinikmod',
    install_path = path_join(BASE_DIR, 'MarketHelper.lua'),
    accent       = imgui.ImVec4(1.00, 0.75, 0.15, 1.00),
    button       = imgui.ImVec4(0.10, 0.36, 0.14, 1.00),
}

local FH = {
    key          = 'fh',
    title        = 'Fam Helper',
    github_user  = 'ShiNiK-Dev',
    github_repo  = 'FamHelper',
    file         = 'FamHelper.lua',
    author       = 'Shinik_Pupckin',
    tg           = 'https://t.me/shinikmod',
    install_path = path_join(BASE_DIR, 'FamHelper.lua'),
    accent       = imgui.ImVec4(0.40, 1.00, 0.60, 1.00),
    button       = imgui.ImVec4(0.10, 0.36, 0.14, 1.00),
}

local scripts = { MH, FH }
for _, cfg in ipairs(scripts) do
    cfg.api_release = ('https://api.github.com/repos/%s/%s/releases/latest'):format(cfg.github_user, cfg.github_repo)
    cfg.api_tags    = ('https://api.github.com/repos/%s/%s/tags'):format(cfg.github_user, cfg.github_repo)
    cfg.raw_main    = ('https://raw.githubusercontent.com/%s/%s/main/%s'):format(cfg.github_user, cfg.github_repo, cfg.file)
    cfg.raw_master  = ('https://raw.githubusercontent.com/%s/%s/master/%s'):format(cfg.github_user, cfg.github_repo, cfg.file)
    cfg.release_dl  = ('https://github.com/%s/%s/releases/latest/download/%s'):format(cfg.github_user, cfg.github_repo, cfg.file)
end

local wnd_open = imgui.new.bool(false)
local tab_idx  = 0

local state = {
    mh = {
        ver_local = '?',
        ver_remote = nil,
        upd = false,
        checking = false,
        dl_state = nil,
        progress = 0,
        status_text = '',
        status_color = imgui.ImVec4(0.75, 0.75, 0.75, 1.00),
    },
    fh = {
        ver_local = '?',
        ver_remote = nil,
        upd = false,
        checking = false,
        dl_state = nil,
        progress = 0,
        status_text = '',
        status_color = imgui.ImVec4(0.75, 0.75, 0.75, 1.00),
    },
}

local COLOR_INFO    = imgui.ImVec4(0.45, 0.80, 1.00, 1.00)
local COLOR_OK      = imgui.ImVec4(0.35, 1.00, 0.45, 1.00)
local COLOR_WARN    = imgui.ImVec4(1.00, 0.78, 0.20, 1.00)
local COLOR_ERROR   = imgui.ImVec4(1.00, 0.45, 0.35, 1.00)
local COLOR_MUTED   = imgui.ImVec4(0.65, 0.65, 0.65, 1.00)

local function chat(msg, color)
    if isSampAvailable() then
        sampAddChatMessage('[MarketLauncher] ' .. u8(msg), color or 0xFFFFFF)
    end
end

local function set_status(st, text, color)
    st.status_text = text or ''
    st.status_color = color or COLOR_MUTED
end

local function clamp01(x)
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local function open_url(url)
    if not url or url == '' then
        chat('{ff7777}Ссылка не указана.', 0xFFFFFF)
        return false
    end

    local link = url
    if not link:match('^https?://') then
        if link:match('^t%.me/') or link:match('^telegram%.me/') then
            link = 'https://' .. link
        else
            link = 'https://' .. link
        end
    end

    local ok
    if package.config:sub(1, 1) == '\\' then
        ok = os.execute('start "" "' .. link .. '"')
    else
        ok = os.execute('am start -a android.intent.action.VIEW -d "' .. link .. '" >/dev/null 2>&1')
    end

    if ok == true or ok == 0 then
        return true
    end

    chat('{ff7777}Не удалось открыть ссылку: {ffffff}' .. link, 0xFFFFFF)
    return false
end

local function ver_lt(a, b)
    local function parts(s)
        local t = {}
        for p in (s or '0'):gmatch('%d+') do
            t[#t + 1] = tonumber(p)
        end
        return t
    end

    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local ai, bi = pa[i] or 0, pb[i] or 0
        if ai < bi then return true end
        if ai > bi then return false end
    end
    return false
end

local function normalize_ver(v)
    if not v or v == '' then return nil end
    return tostring(v):gsub('^[vV]', '')
end

local function read_ver(path)
    local f = io.open(path, 'r')
    if not f then return '?' end
    for _ = 1, 120 do
        local ln = f:read('*l')
        if not ln then break end
        local v = ln:match('script_version%s*%(%s*["\']([^"\']+) ["\']')
        if v then
            f:close()
            return normalize_ver(v) or '?'
        end
    end
    f:close()
    return '?'
end

local function version_from_body(body)
    if not body or body == '' then return nil end
    return normalize_ver(body:match('script_version%s*%(%s*["\']([^"\']+) ["\']'))
end

local function is_valid_script_body(body, expected_file)
    if type(body) ~= 'string' or #body < 150 then
        return false
    end
    if body:find('<!DOCTYPE html', 1, true) or body:find('<html', 1, true) then
        return false
    end
    if body:find('Not Found', 1, true) and #body < 400 then
        return false
    end
    if body:find('script_name%s*%(') or body:find('function%s+main%s*%(') then
        return true
    end
    if expected_file and body:find(expected_file, 1, true) then
        return true
    end
    return false
end

local function write_file_atomic(path, content)
    local tmp = path .. '.tmp'
    local f = io.open(tmp, 'wb')
    if not f then return false end
    f:write(content)
    f:close()

    os.remove(path)
    if os.rename(tmp, path) then
        return true
    end

    local rf = io.open(tmp, 'rb')
    local wf = io.open(path, 'wb')
    if not rf or not wf then
        if rf then rf:close() end
        if wf then wf:close() end
        os.remove(tmp)
        return false
    end
    wf:write(rf:read('*a'))
    rf:close()
    wf:close()
    os.remove(tmp)
    return true
end

local function parse_release_version(body)
    return normalize_ver(body and body:match('"tag_name"%s*:%s*"([^"]+)"'))
end

local function parse_first_tag(body)
    return normalize_ver(body and body:match('"name"%s*:%s*"([^"]+)"'))
end

local function http_fetch(url)
    return effil.thread(function(target)
        local req = require('requests')

        local function once(link, depth)
            depth = depth or 0
            if depth > 5 then
                return false, { status_code = 0, text = '', error = 'redirect loop' }
            end

            local ok, response = pcall(req.request, 'GET', link, {
                headers = {
                    ['User-Agent'] = 'MarketLauncher/1.1',
                    ['Accept'] = 'application/vnd.github+json, application/octet-stream;q=0.9, text/plain;q=0.8, */*;q=0.7',
                },
                timeout = 20,
            })

            if not ok or not response then
                return false, { status_code = 0, text = '', error = tostring(response or 'connect error') }
            end

            local code = tonumber(response.status_code) or 0
            if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
                local loc = response.headers and (response.headers.Location or response.headers.location)
                if loc and loc ~= '' then
                    return once(loc, depth + 1)
                end
            end

            return true, {
                status_code = code,
                text = response.text or '',
                headers = response.headers or {},
                error = nil,
            }
        end

        return once(target, 0)
    end)(url)
end

local function finish_check(cfg, st, remote_ver, silent)
    st.checking = false
    st.ver_remote = normalize_ver(remote_ver)
    st.ver_local = read_ver(cfg.install_path)
    st.upd = st.ver_remote and (st.ver_local == '?' or ver_lt(st.ver_local, st.ver_remote)) or false

    if not st.ver_remote then
        set_status(st, 'Не удалось определить версию на GitHub.', COLOR_ERROR)
        if not silent then
            chat('{ff7777}' .. cfg.title .. ': {ffffff}не удалось определить актуальную версию на GitHub.', 0xFFFFFF)
        end
        return
    end

    if st.ver_local == '?' then
        set_status(st, 'Доступна версия v' .. st.ver_remote .. ' для установки.', COLOR_INFO)
        if not silent then
            chat('{66ccff}' .. cfg.title .. ': {ffffff}доступна версия v' .. st.ver_remote .. ' для установки.', 0xFFFFFF)
        end
    elseif st.upd then
        set_status(st, 'Доступно обновление до v' .. st.ver_remote .. '.', COLOR_WARN)
        if not silent then
            chat('{ffcc55}' .. cfg.title .. ': {ffffff}доступно обновление до v' .. st.ver_remote .. '.', 0xFFFFFF)
        end
    else
        set_status(st, 'Установлена актуальная версия v' .. st.ver_local .. '.', COLOR_OK)
        if not silent then
            chat('{aaffaa}' .. cfg.title .. ': {ffffff}установлена актуальная версия v' .. st.ver_local .. '.', 0xFFFFFF)
        end
    end
end

local function do_check(cfg, st, silent)
    if st.checking or st.dl_state == 'working' then return end

    st.checking = true
    st.ver_remote = nil
    st.upd = false
    set_status(st, 'Проверка обновлений...', COLOR_MUTED)

    lua_thread.create(function()
        local sources = {
            { url = cfg.api_release, mode = 'release' },
            { url = cfg.api_tags,    mode = 'tags'    },
            { url = cfg.raw_main,    mode = 'raw'     },
            { url = cfg.raw_master,  mode = 'raw'     },
        }

        for _, item in ipairs(sources) do
            local thr = http_fetch(item.url)
            local done = false

            for _ = 1, 180 do
                wait(100)
                local status_ok, thread_state = thr:status()
                if not status_ok or thread_state == 'canceled' then
                    done = true
                    break
                end

                if thread_state == 'completed' then
                    local ok, response = thr:get()
                    if ok and response and tonumber(response.status_code) == 200 and response.text ~= '' then
                        local remote_ver
                        if item.mode == 'release' then
                            remote_ver = parse_release_version(response.text)
                        elseif item.mode == 'tags' then
                            remote_ver = parse_first_tag(response.text)
                        else
                            remote_ver = version_from_body(response.text)
                        end

                        if remote_ver then
                            finish_check(cfg, st, remote_ver, silent)
                            return
                        end
                    end
                    done = true
                    break
                end
            end

            if not done then
                -- переход к следующему источнику
            end
        end

        st.checking = false
        st.ver_remote = nil
        st.upd = false
        set_status(st, 'Ошибка проверки GitHub.', COLOR_ERROR)
        if not silent then
            chat('{ff7777}' .. cfg.title .. ': {ffffff}не удалось проверить GitHub. Проверь репозиторий, релиз или доступность файла.', 0xFFFFFF)
        end
    end)
end

local function do_download(cfg, st)
    if st.dl_state == 'working' then return end

    st.dl_state = 'working'
    st.progress = 0
    set_status(st, 'Подготовка загрузки...', COLOR_INFO)

    lua_thread.create(function()
        local sources = {
            { url = cfg.release_dl, name = 'release' },
            { url = cfg.raw_main,   name = 'main'    },
            { url = cfg.raw_master, name = 'master'  },
        }

        for _, item in ipairs(sources) do
            local thr = http_fetch(item.url)

            for _ = 1, 260 do
                wait(120)
                if st.progress < 95 then
                    st.progress = math.min(95, st.progress + 1.5)
                end

                local status_ok, thread_state = thr:status()
                if not status_ok or thread_state == 'canceled' then
                    break
                end

                if thread_state == 'completed' then
                    local ok, response = thr:get()
                    if ok and response and tonumber(response.status_code) == 200 then
                        local body = response.text or ''
                        if is_valid_script_body(body, cfg.file) then
                            if write_file_atomic(cfg.install_path, body) then
                                st.progress = 100
                                st.dl_state = 'done'
                                st.ver_local = read_ver(cfg.install_path)
                                st.ver_remote = st.ver_remote or version_from_body(body) or st.ver_local
                                st.upd = false
                                set_status(st, 'Скрипт успешно загружен. При необходимости введи /reloadscripts.', COLOR_OK)
                                chat('{aaffaa}' .. cfg.title .. ': {ffffff}скрипт успешно загружен. Если он не появился сразу — введи /reloadscripts.', 0xFFFFFF)
                                return
                            else
                                st.dl_state = 'error'
                                set_status(st, 'Ошибка записи файла в папку MoonLoader.', COLOR_ERROR)
                                chat('{ff7777}' .. cfg.title .. ': {ffffff}не удалось сохранить файл в папку MoonLoader.', 0xFFFFFF)
                                return
                            end
                        end
                    end
                    break
                end
            end
        end

        st.progress = 0
        st.dl_state = 'error'
        set_status(st, 'Не удалось загрузить скрипт с GitHub.', COLOR_ERROR)
        chat('{ff7777}' .. cfg.title .. ': {ffffff}не удалось загрузить скрипт с GitHub. Проверь релиз, ветку main/master и имя файла.', 0xFFFFFF)
    end)
end

function main()
    while not isSampLoaded() do
        wait(500)
    end
    while not isSampAvailable() do
        wait(500)
    end
    wait(1500)

    state.mh.ver_local = read_ver(MH.install_path)
    state.fh.ver_local = read_ver(FH.install_path)

    sampRegisterChatCommand('ml', function()
        wnd_open[0] = not wnd_open[0]
    end)

    chat('{66ccff}Скрипт загружен. Открыть меню: {ffffff}/ml', 0xFFFFFF)

    lua_thread.create(function()
        wait(3500)
        do_check(MH, state.mh, true)
        do_check(FH, state.fh, true)
    end)

    local last_check = os.time()
    while true do
        wait(0)
        if os.time() - last_check >= 300 then
            last_check = os.time()
            do_check(MH, state.mh, true)
            do_check(FH, state.fh, true)
        end
    end
end

local function col_btn(r, g, b, label, w, h)
    local hovered = imgui.ImVec4(clamp01(r + 0.08), clamp01(g + 0.08), clamp01(b + 0.08), 1.00)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, 1.00))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, hovered)
    imgui.PushStyleColor(imgui.Col.ButtonActive, hovered)
    local clicked = imgui.Button(label, imgui.ImVec2(w, h))
    imgui.PopStyleColor(3)
    return clicked
end

local function centered_text(region_w, color, text)
    local tw = imgui.CalcTextSize(text).x
    imgui.SetCursorPosX(math.max((region_w - tw) * 0.5, 0))
    imgui.TextColored(color, text)
end

local function draw_versions(region_w, st)
    local left_w = math.floor(region_w * 0.52)
    imgui.Columns(2, '##versions', false)
    imgui.SetColumnWidth(0, left_w)

    imgui.TextColored(COLOR_MUTED, 'Установленная версия:')
    imgui.NextColumn()
    if st.ver_local == '?' then
        imgui.TextColored(COLOR_WARN, 'Не установлен')
    else
        imgui.TextColored(COLOR_OK, 'v' .. st.ver_local)
    end
    imgui.NextColumn()

    imgui.TextColored(COLOR_MUTED, 'Актуальная версия:')
    imgui.NextColumn()
    if st.checking then
        imgui.TextColored(COLOR_MUTED, 'Проверка...')
    elseif st.ver_remote then
        if st.upd then
            imgui.TextColored(COLOR_WARN, 'v' .. st.ver_remote .. ' (доступно)')
        else
            imgui.TextColored(COLOR_OK, 'v' .. st.ver_remote)
        end
    else
        imgui.TextColored(COLOR_MUTED, 'Не определена')
    end
    imgui.NextColumn()
    imgui.Columns(1)
end

local function draw_progress(region_w, st)
    if st.dl_state ~= 'working' then return end
    imgui.Dummy(imgui.ImVec2(0, 10))
    imgui.TextColored(COLOR_INFO, 'Загрузка файла...')
    imgui.ProgressBar((st.progress or 0) / 100, imgui.ImVec2(region_w, 14), tostring(math.floor(st.progress or 0)) .. '%')
end

local function draw_status(st)
    if not st.status_text or st.status_text == '' then return end
    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.PushTextWrapPos(0.0)
    imgui.TextColored(st.status_color, st.status_text)
    imgui.PopTextWrapPos()
end

local function draw_link_button(label, url, id, region_w)
    imgui.TextColored(COLOR_MUTED, label)
    if col_btn(0.10, 0.27, 0.55, url .. '##' .. id, region_w, 34) then
        open_url(url)
    end
end

local function draw_download_block(region_w, cfg, st)
    imgui.Dummy(imgui.ImVec2(0, 18))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 16))

    if st.upd and st.ver_remote then
        if col_btn(0.44, 0.26, 0.04, 'Обновить до v' .. st.ver_remote, region_w, 48) then
            do_download(cfg, st)
        end
    else
        local title = (st.ver_local == '?' and 'Скачать ' or 'Переустановить ') .. cfg.title
        if st.dl_state == 'working' then
            col_btn(0.20, 0.20, 0.20, 'Идёт загрузка...', region_w, 48)
        else
            if col_btn(cfg.button.x, cfg.button.y, cfg.button.z, title, region_w, 48) then
                do_download(cfg, st)
            end
        end
    end

    imgui.Dummy(imgui.ImVec2(0, 8))
    if col_btn(0.12, 0.18, 0.30, 'Проверить обновления', region_w, 40) then
        do_check(cfg, st, false)
    end

    draw_progress(region_w, st)
    draw_status(st)
end

local function draw_close_btn(region_w, id)
    imgui.Dummy(imgui.ImVec2(0, 8))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 6))
    if col_btn(0.28, 0.07, 0.07, 'Закрыть##' .. id, region_w, 40) then
        wnd_open[0] = false
    end
end

local function draw_script_tab(cfg, st, region_w)
    centered_text(region_w, cfg.accent, cfg.title)
    imgui.Dummy(imgui.ImVec2(0, 6))

    local author_text = 'Автор: ' .. cfg.author
    local total_w = imgui.CalcTextSize(author_text).x + 100
    imgui.SetCursorPosX(math.max((region_w - total_w) * 0.5, 0))
    imgui.TextColored(COLOR_INFO, author_text)
    imgui.SameLine(0, 10)
    if imgui.Button('Telegram##' .. cfg.key, imgui.ImVec2(90, 0)) then
        open_url(cfg.tg)
    end

    imgui.Dummy(imgui.ImVec2(0, 12))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 12))

    draw_versions(region_w, st)
    draw_download_block(region_w, cfg, st)
end

local function draw_about_tab(region_w)
    imgui.TextColored(imgui.ImVec4(1.00, 0.75, 0.15, 1.00), 'О скрипте')
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 12))

    imgui.TextColored(MH.accent, MH.title)
    imgui.TextColored(COLOR_MUTED, 'Автор:')
    imgui.SameLine()
    imgui.TextColored(COLOR_INFO, MH.author)
    imgui.TextColored(COLOR_MUTED, 'Версия:')
    imgui.SameLine()
    if state.mh.ver_local == '?' then
        imgui.TextColored(COLOR_WARN, 'Не установлен')
    else
        imgui.TextColored(COLOR_OK, 'v' .. state.mh.ver_local)
    end

    imgui.Dummy(imgui.ImVec2(0, 8))

    imgui.TextColored(FH.accent, FH.title)
    imgui.TextColored(COLOR_MUTED, 'Автор:')
    imgui.SameLine()
    imgui.TextColored(COLOR_INFO, FH.author)
    imgui.TextColored(COLOR_MUTED, 'Версия:')
    imgui.SameLine()
    if state.fh.ver_local == '?' then
        imgui.TextColored(COLOR_WARN, 'Не установлен')
    else
        imgui.TextColored(COLOR_OK, 'v' .. state.fh.ver_local)
    end

    imgui.Dummy(imgui.ImVec2(0, 14))
    imgui.Separator()
    imgui.Dummy(imgui.ImVec2(0, 12))

    imgui.TextColored(COLOR_INFO, 'Связь с разработчиком')
    imgui.Dummy(imgui.ImVec2(0, 6))
    draw_link_button('Telegram канал', MH.tg, 'about_tg1', region_w)
    imgui.Dummy(imgui.ImVec2(0, 8))
    draw_link_button('Техподдержка', MH.tg, 'about_tg2', region_w)
end

imgui.OnFrame(
    function()
        return wnd_open[0]
    end,
    function()
        local sw, sh = imgui.GetIO().DisplaySize.x, imgui.GetIO().DisplaySize.y
        local ww, wh = 800, 680

        imgui.SetNextWindowSize(imgui.ImVec2(ww, wh), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2((sw - ww) * 0.5, (sh - wh) * 0.5), imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0.97)

        local flags = imgui.WindowFlags.NoCollapse
            + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoTitleBar
            + imgui.WindowFlags.NoMove

        if not imgui.Begin('##ml', wnd_open, flags) then
            imgui.End()
            return
        end

        local tabs = { 'Market Helper', 'Fam Helper', 'О скрипте' }
        local content_w = imgui.GetWindowContentRegionWidth()
        local tab_w = (content_w - (#tabs - 1) * 4) / #tabs

        for i = 0, #tabs - 1 do
            local active = (tab_idx == i)
            local color = active and imgui.ImVec4(0.14, 0.40, 0.70, 1.00) or imgui.ImVec4(0.14, 0.14, 0.17, 1.00)
            imgui.PushStyleColor(imgui.Col.Button, color)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(clamp01(color.x + 0.08), clamp01(color.y + 0.08), clamp01(color.z + 0.08), 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(clamp01(color.x + 0.08), clamp01(color.y + 0.08), clamp01(color.z + 0.08), 1.00))
            if imgui.Button(tabs[i + 1] .. '##tab' .. i, imgui.ImVec2(tab_w, 36)) then
                tab_idx = i
            end
            imgui.PopStyleColor(3)
            if i < #tabs - 1 then
                imgui.SameLine(0, 4)
            end
        end

        imgui.Separator()
        imgui.Dummy(imgui.ImVec2(0, 8))

        local footer_h = 62
        if imgui.BeginChild('##ml_content', imgui.ImVec2(0, -footer_h), false) then
            local region_w = imgui.GetWindowContentRegionWidth()

            if tab_idx == 0 then
                draw_script_tab(MH, state.mh, region_w)
            elseif tab_idx == 1 then
                draw_script_tab(FH, state.fh, region_w)
            else
                draw_about_tab(region_w)
            end
        end
        imgui.EndChild()

        draw_close_btn(imgui.GetWindowContentRegionWidth(), 'main')
        imgui.End()
    end
)