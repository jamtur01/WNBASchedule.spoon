local obj = {}
obj.__index = obj

-- Metadata
obj.name = "WNBASchedule"
obj.version = "2.8"
obj.author = "James Turnbull <james@lovedthanlost.net>"
obj.homepage = "https://github.com/jamtur01/WNBASchedule.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Constants
local SCHEDULE_URL = "https://cdn.espn.com/core/wnba/schedule?xhr=1&limit=100"
local REFRESH_INTERVAL = 3600

-- Helper functions
local function fetchSchedule(callback)
    hs.http.asyncGet(SCHEDULE_URL, nil, function(status, body, headers)
        if status ~= 200 then
            obj.logger.e("Error fetching schedule:", status)
            callback(nil)
            return
        end
        local scheduleData = hs.json.decode(body)
        callback(scheduleData)
    end)
end

local function parseGames(data)
    local games = {}
    if data and data.content and data.content.schedule then
        for date, dateData in pairs(data.content.schedule) do
            if dateData.games then
                for _, game in ipairs(dateData.games) do
                    local homeScore = game.competitions[1].competitors[1].score
                    local awayScore = game.competitions[1].competitors[2].score
                    table.insert(games, {
                        date = date,
                        time = game.date,
                        url  = game.links[1].href,
                        home = game.competitions[1].competitors[1].team.shortDisplayName,
                        away = game.competitions[1].competitors[2].team.shortDisplayName,
                        homeScore = homeScore,
                        awayScore = awayScore,
                        status = game.status.type.state
                    })
                end
            end
        end
    end
    return games
end

local function formatGameTime(timeString)
    local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+)"
    local year, month, day, hour, min = timeString:match(pattern)
    if year then
        local timestamp = os.time({year=year, month=month, day=day, hour=hour, min=min})
        local etTime = timestamp - 4 * 3600
        return os.date("%I:%M %p ET", etTime)
    end
    return "Time TBA"
end

local function getDaySuffix(day)
    if day >= 11 and day <= 13 then return "th" end
    local suffixes = {[1] = "st", [2] = "nd", [3] = "rd"}
    return suffixes[day % 10] or "th"
end

local function formatGameDate(dateString)
    local pattern = "(%d%d%d%d)(%d%d)(%d%d)"
    local year, month, day = dateString:match(pattern)
    if year then
        local timestamp = os.time({year=year, month=month, day=day})
        local dayOfWeek = os.date("%a", timestamp)
        local monthName = os.date("%b", timestamp)
        local dayNum = tonumber(day)
        local suffix = getDaySuffix(dayNum)
        return string.format("%s %s %d%s", dayOfWeek, monthName, dayNum, suffix)
    end
    return "Date Unknown"
end

local function sortGames(games)
    table.sort(games, function(a, b)
        return a.date == b.date and a.time < b.time or a.date < b.date
    end)
end

local function isFavoriteTeam(game, favoriteTeams)
    for _, team in ipairs(favoriteTeams) do
        if game.home == team or game.away == team then
            return true
        end
    end
    return false
end

-- Object methods
function obj:init()
    self.menubar = nil
    self.logger = hs.logger.new('WNBASchedule', 'info')
    self:loadSettings()
    return self
end

function obj:loadSettings()
    self.favoriteTeams = hs.settings.get("favoriteTeams") or {}
end

function obj:saveSettings()
    hs.settings.set("favoriteTeams", self.favoriteTeams)
end

function obj:updateMenu()
    fetchSchedule(function(scheduleData)
        if not scheduleData then 
            hs.notify.new({title="WNBA Schedule Error", informativeText="Failed to fetch WNBA schedule"}):send()
            return 
        end

        local games = parseGames(scheduleData)
        
        if #games == 0 then
            hs.notify.new({title="WNBA Schedule", informativeText="No WNBA games found"}):send()
            return
        end
        
        sortGames(games)
        
        local menuItems = {}
        local upcomingGames = {}
        local pastGames = {}
        local liveGames = {}
        
        for _, game in ipairs(games) do
            if isFavoriteTeam(game, self.favoriteTeams) then
                if game.status == "pre" then
                    table.insert(upcomingGames, game)
                elseif game.status == "post" then
                    table.insert(pastGames, game)
                elseif game.status == "in" then
                    table.insert(liveGames, game)
                end
            end
        end
        
        if #liveGames > 0 then
            table.insert(menuItems, {title = "Live Games", disabled = true})
            for _, game in ipairs(liveGames) do
                local gameDate = formatGameDate(game.date)
                local title = string.format("%s %s - %s %s (%s)", game.away, game.awayScore, game.home, game.homeScore, gameDate)
                table.insert(menuItems, {
                    title = title,
                    fn = function() hs.urlevent.openURL(game.url) end,
                    tooltip = gameDate
                })
            end
            table.insert(menuItems, {title = "-"})
        end
        
        if #upcomingGames > 0 then
            table.insert(menuItems, {title = "Upcoming Games", disabled = true})
            for _, game in ipairs(upcomingGames) do
                local gameDate = formatGameDate(game.date)
                local gameTime = formatGameTime(game.time)
                local title = string.format("%s vs %s - %s at %s", game.away, game.home, gameDate, gameTime)
                table.insert(menuItems, {
                    title = title,
                    fn = function() hs.urlevent.openURL(game.url) end,
                    tooltip = string.format("%s at %s", gameDate, gameTime)
                })
            end
            table.insert(menuItems, {title = "-"})
        end
        
        if #pastGames > 0 then
            table.insert(menuItems, {title = "Past Games", disabled = true})
            for _, game in ipairs(pastGames) do
                local gameDate = formatGameDate(game.date)
                local title = string.format("%s %s - %s %s (%s)", game.away, game.awayScore, game.home, game.homeScore, gameDate)
                table.insert(menuItems, {
                    title = title,
                    fn = function() hs.urlevent.openURL(game.url) end,
                    tooltip = gameDate
                })
            end
        end
        
        if #menuItems == 0 then 
            table.insert(menuItems, {title = "No games found for your favorite teams"})
        end

        self.menubar:setMenu(menuItems)
    end)
end

function obj:start()
    if self.menubar then
        self.menubar:delete()
    end
    self.menubar = hs.menubar.new()
    
    local logoPath = hs.spoons.resourcePath("basketball-logo.png")
    local logoImage = hs.image.imageFromPath(logoPath)

    if logoImage then
        self.menubar:setIcon(logoImage)
    else
        self.menubar:setTitle("W")
    end

    self.menubar:setTooltip("WNBA Schedule")
    self:updateMenu()
    
    hs.timer.doEvery(REFRESH_INTERVAL, function() self:updateMenu() end)
end

function obj:stop()
    if self.menubar then
        self.menubar:delete()
        self.menubar = nil
    end
end

return obj