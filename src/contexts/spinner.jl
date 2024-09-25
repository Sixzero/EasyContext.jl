
@kwdef mutable struct LoadingSpinner
	running::Ref{Bool}=true
end
function (sp::LoadingSpinner)()
	p = ProgressUnknown("Progressing...", spinner=true)
	@async_showerr begin
			while !istaskdone(current_task()) && sp.running[]
					ProgressMeter.next!(p)  # Update spinner without incrementing progress
					sleep(0.05)
			end
	end
end

stop_spinner(spinner::LoadingSpinner)= spinner.running[]=false
