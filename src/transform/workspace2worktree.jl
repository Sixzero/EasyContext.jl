ws2wt!(ws, p, conv) = begin
	for (i, projpath) in enumerate(ws.project_paths)
		ws.project_paths[i] = joinpath(p.path, conv.id, projpath)
	end
	ws.root_path, ws.rel_project_paths = resolve(ws.resolution_method, ws.project_paths)

end