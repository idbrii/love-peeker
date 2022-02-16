--[[
MIT License

Copyright (c) 2021 Brandon Blanker Lim-it

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

local Peeker = {}

local DEF_FPS = 30
local MAX_N_THREAD = love.system.getProcessorCount()
local OS = love.system.getOS()

local thread_code = [[
require("love.image")
local channel, i, out_dir = ...
local image_data = channel:demand()
local filename = string.format("%04d.png", i)
filename = out_dir .. "/" .. filename
local res = image_data:encode("png", filename)
if res then
	love.thread.getChannel("status"):push(i)
else
	print(i, res)
end
]]

local workers = {}
local timer, cur_frame = 0, 0
local is_recording = false

local supported_formats = {"mp4", "mkv", "webm"}
local str_supported_formats = table.concat(supported_formats)
local OPT = {}

local function sassert(var, cond, msg)
	if var == nil then return end
	if not cond then error(msg) end
end

local function within_itable(v, t)
	for _, v2 in ipairs(t) do
		if v == v2 then return true end
	end
	return false
end

local function unique_filename(filepath, format)
	local orig = filepath
	if format then
		format = ".".. format
	else
		format = ""
	end
	filepath = orig .. format
	local n = 0
	while love.filesystem.getInfo(filepath) do
		n = n + 1
		filepath = orig .. n .. format
	end
	return filepath
end

function Peeker.start(opt)
	assert(type(opt) == "table")
	sassert(opt.n_threads, type(opt.n_threads) == "number" and opt.n_threads > 0,
		"opt.n_threads must be a positive integer")
	sassert(opt.n_threads, opt.n_threads and opt.n_threads <= MAX_N_THREAD,
		"opt.n_threads should not be > " .. MAX_N_THREAD .. " max available threads")
	sassert(opt.fps, type(opt.fps) == "number" and opt.fps > 0,
		"opt.fps must be a positive integer")
	sassert(opt.out_dir, type(opt.out_dir) == "string",
		"opt.out_dir must be a string")
	sassert(opt.format, type(opt.format) == "string"
		and within_itable(opt.format, supported_formats),
		"opt.format must be either: " .. str_supported_formats)
	sassert(opt.post_clean_frames, type(opt.post_clean_frames) == "boolean")

	OPT = opt

	OPT.n_threads = OPT.n_threads or MAX_N_THREAD
	OPT.fps = OPT.fps or DEF_FPS
	OPT.format = OPT.format or "mp4"
	OPT.out_dir = OPT.out_dir or string.format("recording_" .. os.time())

	OPT.out_dir = unique_filename(OPT.out_dir)
	love.filesystem.createDirectory(OPT.out_dir)

	for i = 1, OPT.n_threads do
		local channel_name = "peeker_".. i
		workers[i] = {
			thread = love.thread.newThread(thread_code:format(i)),
			channel = love.thread.getChannel(channel_name),
		}
	end

	cur_frame = 0
	timer = 0
	is_recording = true
end

function Peeker.stop(finalize)
	sassert(finalize, type(finalize) == "boolean")
	is_recording = false
	if not finalize then return end

	local path = Peeker.get_out_dir()
	local flags = ""
	local cmd

	if OPT.format == "mp4" then
		flags = "-filter:v format=yuv420p -movflags +faststart"
	end

	local out_file = "../".. unique_filename(OPT.out_dir, OPT.format)

	if OS == "Linux" then
		local cmd_ffmpeg = string.format("ffmpeg -framerate %d -i '%%04d.png' %s %s;",
			OPT.fps, flags, out_file)
		local cmd_cd = string.format("cd '%s'", path)
		cmd = string.format("bash -c '%s && %s'", cmd_cd, cmd_ffmpeg)
	elseif OS == "Windows" then
		local cmd_ffmpeg = string.format("ffmpeg -framerate %d -i %%04d.png %s %s",
			OPT.fps, flags, out_file)
		local cmd_cd = string.format("cd /d %q", path)
		cmd = string.format("%s && %s", cmd_cd, cmd_ffmpeg)
	end

	if cmd then
		print(cmd)
		local res = os.execute(cmd)
		local msg = res == 0 and "OK" or "PROBLEM ENCOUNTERED"
		print("Video creation status: " .. msg)

		if res == 0 and OPT.post_clean_frames then
			print("cleaning: " .. OPT.out_dir)
			for _, file in ipairs(love.filesystem.getDirectoryItems(OPT.out_dir)) do
				love.filesystem.remove(OPT.out_dir .. "/" .. file)
			end

			local res_rmd = love.filesystem.remove(OPT.out_dir)
			print("removed dir: " .. tostring(res_rmd))
		end
	end
end

function Peeker.update(dt)
	if not is_recording then return end
	timer = timer + dt
	local found = false
	for _, w in ipairs(workers) do
		if not w.thread:isRunning() then
			love.graphics.captureScreenshot(w.channel)
			w.thread:start(w.channel, cur_frame, OPT.out_dir)
			found = true
			break
		end

		local err = w.thread:getError()
		if err then
			print(err)
		end
	end

	if not found then
		for _, w in ipairs(workers) do
			w.thread:wait()
			break
		end
	end

	local status = love.thread.getChannel("status"):pop()
	if status then cur_frame = cur_frame + 1 end
end

function Peeker.get_status() return is_recording end
function Peeker.get_current_frame() return cur_frame end
function Peeker.get_out_dir()
	return love.filesystem.getSaveDirectory() .."/".. OPT.out_dir
end

return Peeker
