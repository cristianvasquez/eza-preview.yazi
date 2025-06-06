local M = {}

local function fail(s, ...)
	ya.notify({
		title = "Eza Preview",
		content = string.format(s, ...),
		timeout = 5,
		level = "error"
	})
end

local toggle_view_mode = ya.sync(function(state, _)
	state.tree = not state.tree
end)

local is_tree_view_mode = ya.sync(function(state, _)
	return state.tree or false
end)

local set_opts = ya.sync(function(state, opts)
	state.opts = state.opts or { level = 3, follow_symlinks = false, dereference = false }

	for key, value in pairs(opts or {}) do
		state.opts[key] = value
	end
end)

local get_opts = ya.sync(function(state)
	state.opts = state.opts or { level = 3, follow_symlinks = false, dereference = false }
	return state.opts
end)

local inc_level = ya.sync(function(state)
	state.opts.level = state.opts.level + 1
end)

local dec_level = ya.sync(function(state)
	if state.opts.level > 1 then
		state.opts.level = state.opts.level - 1
	end
end)

local toggle_follow_symlinks = ya.sync(function(state)
	state.opts.follow_symlinks = not state.opts.follow_symlinks
end)

function M:setup(opts)
	set_opts(opts)
	toggle_view_mode()
end

function M:entry(job)
	local args = job.args

	if args["inc_level"] then
		inc_level()
	elseif args["dec_level"] then
		dec_level()
	elseif args["toggle_follow_symlinks"] then
		toggle_follow_symlinks()
	else
		set_opts()
		toggle_view_mode()
	end

	ya.manager_emit("seek", { 0 })
end

function M:peek(job)
	local opts = get_opts()
	local is_tree = is_tree_view_mode()

	local args = {
		"--all",
		"--color=always",
		"--icons=always",
		"--group-directories-first",
		"--no-quotes",
		tostring(job.file.url),
	}

	if is_tree then
		table.insert(args, "--tree")
		table.insert(args, string.format("--level=%d", opts.level))
	end

	if opts.follow_symlinks then
		table.insert(args, "--follow-symlinks")
	end

	if opts.dereference then
		table.insert(args, "--dereference")
	end

	local child = Command("eza"):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):spawn()

	local limit = job.area.h
	local lines = ""
	local num_lines = 1
	local num_skip = 0
	local empty_output = false

	repeat
		local line, event = child:read_line()
		if event == 1 then
			fail("eza error: %s", line)
			break
		elseif event ~= 0 then
			break
		end

		if num_skip >= job.skip then
			lines = lines .. line
			num_lines = num_lines + 1
		else
			num_skip = num_skip + 1
		end
	until num_lines >= limit

	child:start_kill()

	if (not is_tree and num_lines == 1) or (is_tree and num_lines == 2) then
		empty_output = true
	end

	if job.skip > 0 and num_lines < limit then
		ya.manager_emit("peek", {
			tostring(math.max(0, job.skip - (limit - num_lines))),
			only_if = tostring(job.file.url),
			upper_bound = "",
		})
	elseif empty_output then
		ya.preview_widgets(job, {
			ui.Text({ ui.Line("No items") }):area(job.area):align(ui.Text.CENTER),
		})
	else
		ya.preview_widgets(job, {
			ui.Text.parse(lines):area(job.area)
		})
	end
end

function M:seek(job)
	local hovered = cx.active.current.hovered

	if hovered and hovered.url == job.file.url then
		local step = math.floor(job.units * job.area.h / 10)

		ya.manager_emit("peek", {
			math.max(0, cx.active.preview.skip + step),
			only_if = tostring(job.file.url),
			force = true,
		})
	end
end

return M
