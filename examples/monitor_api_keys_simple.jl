using EasyContext
using JLD2
using Printf

# Display current API key loads from JLD2 file
function show_api_key_stats()
    stats_file = EasyContext.STATS_FILE
    
    if !isfile(stats_file)
        println("No credentials stats file found at: $stats_file")
        return
    end
    
    try
        all_stats = jldopen(stats_file, "r") do file
            Dict(key => file[key] for key in keys(file))
        end
        
        if isempty(all_stats)
            println("No API key stats available")
            return
        end
        
        println("Key Hash         Schema               Tokens  Age(min)")
        println("="^60)
        
        current_time = time()
        sorted_entries = sort(collect(pairs(all_stats)), by=x->x[2]["tokens_used_last_minute"], rev=true)
        
        for (key_hash, state) in sorted_entries
            age_mins = (current_time - Float64(state["last_save_time"])) / 60.0
            schema_name = get(state, "schema_name", "Unknown")
            tokens = Int(state["tokens_used_last_minute"])
            key_preview = key_hash[1:min(12, length(key_hash))] * "..."
            
            @printf("%-16s %-20s %6d %8.1f\n", 
                    key_preview, schema_name, tokens, age_mins)
        end
        
    catch e
        println("Error reading stats file: $e")
    end
end

show_api_key_stats()
