using JLD2
using Base64
using FileIO
using EasyContext
using EasyContext: to_PT_messages
using PromptingTools
using PromptingTools: aigenerate
using StreamCallbacks

function debug_conv_jld2(filepath="conv.jld2")
    println("🔍 Loading conversation data from: $filepath")
    
    if !isfile(filepath)
        println("❌ File not found: $filepath")
        return
    end
    
    try
        # Load with proper type mapping
        data = JLD2.load(filepath)
        println("✅ Successfully loaded JLD2 file")
        println("📋 Keys in file: $(keys(data))")
        
        # # Analyze each component
        # for (key, value) in data
        #     println("\n" * "="^50)
        #     println("🔑 Analyzing: $key")
        #     analyze_component(key, value)
        # end
        
        # # Special focus on conversation messages if present
        # if haskey(data, "conv")
        #     analyze_conversation_images(data["conv"])
        # end
        
        # Try to reconstruct the actual call
        println("\n" * "="^60)
        println("🔄 RECONSTRUCTING THE CALL")
        reconstruct_call(data)
        
    catch e
        println("❌ Error loading JLD2 file: $e")
        println("📋 Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
        return
    end
end

function reconstruct_call(data)
    try
        # Extract the saved parameters
        @load "conv.jld2" conv sys_msg_content model cache api_kwargs
        
        println("✅ Successfully loaded all parameters with @load")
        println("🔧 Reconstructed parameters:")
        println("  📱 Model: $model")
        println("  💾 Cache: $cache")
        println("  ⚙️  API kwargs: $api_kwargs")
        println("  💬 Conversation type: $(typeof(conv))")
        println("  📝 System message length: $(length(sys_msg_content))")
        
        # Convert conversation to PromptingTools messages
        println("\n🔄 Converting to PromptingTools messages...")
        pt_messages = to_PT_messages(conv, sys_msg_content, false) # Enable images
        @show length(conv.messages)
        @show length(conv.messages[1].content)
        @show keys(conv.messages[1].context)
        @show conv.messages[1].content
        
        println("✅ Successfully converted to PT messages")
        println("📨 Number of PT messages: $(length(pt_messages))")
        for (i, msg) in enumerate(pt_messages)
            println("  📧 PT Message $i: $(typeof(msg))")
            @show length(msg.content)
            if msg isa PromptingTools.UserMessageWithImages
                @show length(msg.image_url)
                @show length(msg.image_url[1])
                # println("    🖼️  Has images: $(length(msg.image_url)) URLs, $(length(msg.image_path)) paths")
            end
        end
        return
        
        # Try a test call with a simple model first
        println("\n🧪 Testing with a simple call...")
        try
            # Use a smaller, faster model for testing
            test_response = aigenerate(
                pt_messages;
                model="claude",  # Faster model for testing
                max_tokens=10,   # Very small response
                verbose=true,
                cache=:last,
                api_kwargs,
                # streamcallback=StreamCallback(),
            )
            println("✅ Test call successful!")
            println("📤 Response: $(test_response.content)")
            
        catch test_e
            println("❌ Test call failed: $test_e")
            println("📋 This helps identify the issue:")
            
            # Try to identify the specific problem
            if occursin("image", string(test_e))
                println("  🖼️  Issue seems related to image processing")
                analyze_image_issues(pt_messages)
            elseif occursin("token", string(test_e))
                println("  🎫 Issue seems related to token limits")
            elseif occursin("model", string(test_e))
                println("  🤖 Issue seems related to model selection")
            end
        end
        
    catch e
        println("❌ Failed to reconstruct call: $e")
        println("📋 Stack trace:")
        for (exc, bt) in Base.catch_stack()
            showerror(stdout, exc, bt)
            println()
        end
    end
end

function analyze_image_issues(pt_messages)
    println("🔍 Analyzing image-related issues...")
    
    for (i, msg) in enumerate(pt_messages)
        if msg isa PromptingTools.UserMessageWithImages
            println("  📧 Message $i with images:")
            
            if !isnothing(msg.image_url) && !isempty(msg.image_url)
                println("    🌐 Image URLs: $(length(msg.image_url))")
                for (j, url) in enumerate(msg.image_url)
                    println("      🔗 URL $j length: $(length(url))")
                    if startswith(url, "data:")
                        parts = split(url, ",", limit=2)
                        if length(parts) == 2
                            header, b64_data = parts
                            println("        📋 Header: $header")
                            println("        📦 Base64 length: $(length(b64_data))")
                            
                            # Check if base64 is valid
                            try
                                decoded = base64decode(b64_data)
                                println("        ✅ Base64 valid: $(length(decoded)) bytes")
                            catch
                                println("        ❌ Base64 invalid!")
                            end
                        end
                    end
                end
            end
            
            if !isnothing(msg.image_path) && !isempty(msg.image_path)
                println("    📁 Image paths: $(length(msg.image_path))")
                for path in msg.image_path
                    println("      📄 Path: $path (exists: $(isfile(path)))")
                end
            end
        end
    end
end

function analyze_component(key::String, value)
    println("📊 Type: $(typeof(value))")
    
    if key == "conv"
        analyze_conversation(value)
    elseif key == "sys_msg_content"
        println("📝 System message length: $(length(value)) characters")
        println("🔤 First 200 chars: $(first(value, min(200, length(value))))")
    elseif key == "model"
        println("🤖 Model: $value")
    elseif key == "cache"
        println("💾 Cache: $value")
    elseif key == "api_kwargs"
        println("⚙️  API kwargs: $value")
        analyze_api_kwargs(value)
    else
        println("❓ Unknown key, showing first 100 chars if string-like")
        if value isa AbstractString
            println("📄 Content: $(first(value, min(100, length(value))))")
        end
    end
end

function analyze_conversation(conv)
    println("💬 Conversation type: $(typeof(conv))")
    println("📨 Number of messages: $(length(conv.messages))")
    
    for (i, msg) in enumerate(conv.messages)
        println("\n  📧 Message $i:")
        println("    👤 Role: $(msg.role)")
        println("    📏 Content length: $(length(msg.content))")
        println("    🏷️  Context keys: $(keys(msg.context))")
        
        # Check for images in context
        image_contexts = filter(p -> startswith(p.first, "base64img_"), msg.context)
        if !isempty(image_contexts)
            println("    🖼️  Found $(length(image_contexts)) base64 images")
            for (img_key, img_data) in image_contexts
                analyze_base64_image(img_key, img_data, i)
            end
        end
        
        # Show first 100 chars of content
        content_preview = first(msg.content, min(100, length(msg.content)))
        println("    📄 Content preview: $content_preview")
    end
end

function analyze_base64_image(img_key::String, img_data::String, msg_index::Int)
    println("      🔍 Analyzing image: $img_key")
    println("      📏 Base64 data length: $(length(img_data))")
    
    try
        # Check if it's a valid base64 data URL
        if startswith(img_data, "data:")
            # Extract the actual base64 part
            parts = split(img_data, ",", limit=2)
            if length(parts) == 2
                header, b64_data = parts
                println("      🏷️  MIME header: $header")
                println("      📦 Base64 payload length: $(length(b64_data))")
                
                # Try to decode base64
                try
                    decoded = base64decode(b64_data)
                    println("      ✅ Base64 decode successful, $(length(decoded)) bytes")
                    
                    # Try to save and load as image
                    temp_file = "temp_debug_img_msg$(msg_index)_$(replace(img_key, "base64img_" => "")).png"
                    try
                        write(temp_file, decoded)
                        println("      💾 Saved temp file: $temp_file")

                        # Try to load as image
                        img = load(temp_file)
                        println("      🖼️  Image loaded successfully: $(size(img))")
                        println("      🎨 Image type: $(typeof(img))")
                    catch img_e
                        println("      ❌ Failed to load as image: $img_e")
                    finally
                        rm(temp_file, force=true)
                    end
                    
                catch b64_e
                    println("      ❌ Base64 decode failed: $b64_e")
                end
            else
                println("      ⚠️  Invalid data URL format")
            end
        else
            println("      ⚠️  Not a data URL, trying direct base64 decode")
            try
                decoded = base64decode(img_data)
                println("      ✅ Direct base64 decode successful, $(length(decoded)) bytes")
            catch e
                println("      ❌ Direct base64 decode failed: $e")
            end
        end
        
    catch e
        println("      ❌ Error analyzing image: $e")
    end
end

function analyze_api_kwargs(kwargs)
    for (k, v) in pairs(kwargs)
        println("    🔧 $k: $v ($(typeof(v)))")
        
        # Special analysis for thinking parameter
        if k == :thinking && v isa NamedTuple
            println("      🧠 Thinking config:")
            for (tk, tv) in pairs(v)
                println("        • $tk: $tv")
            end
        end
    end
end

function analyze_conversation_images(conv)
    println("\n" * "="^50)
    println("🖼️  DETAILED IMAGE ANALYSIS")
    
    total_images = 0
    for (i, msg) in enumerate(conv.messages)
        image_contexts = filter(p -> startswith(p.first, "base64img_"), msg.context)
        total_images += length(image_contexts)
        
        if !isempty(image_contexts)
            println("\n📧 Message $i has $(length(image_contexts)) images:")
            for (img_key, img_data) in image_contexts
                validate_image_thoroughly(img_key, img_data, i)
            end
        end
    end
    
    println("\n📊 Total images found: $total_images")
end

function validate_image_thoroughly(img_key::String, img_data::String, msg_index::Int)
    println("  🔬 Thorough validation of: $img_key")
    
    # Check data URL format
    if !startswith(img_data, "data:")
        println("    ❌ Not a data URL")
        return false
    end
    
    parts = split(img_data, ",", limit=2)
    if length(parts) != 2
        println("    ❌ Invalid data URL structure")
        return false
    end
    
    header, b64_data = parts
    println("    📋 Header: $header")
    
    # Validate MIME type
    if !occursin("image/", header)
        println("    ⚠️  Header doesn't indicate image MIME type")
    end
    
    # Check base64 validity
    try
        decoded = base64decode(b64_data)
        println("    ✅ Base64 valid, $(length(decoded)) bytes")
        
        # Check if it looks like image data (magic numbers)
        if length(decoded) >= 4
            magic = decoded[1:min(4, length(decoded))]
            magic_hex = join([string(b, base=16, pad=2) for b in magic])
            println("    🔮 Magic bytes: $magic_hex")
            
            # Common image format signatures
            if magic[1:2] == [0xFF, 0xD8]
                println("    🎯 Detected: JPEG")
            elseif magic == [0x89, 0x50, 0x4E, 0x47]
                println("    🎯 Detected: PNG")
            elseif magic[1:2] == [0x47, 0x49]
                println("    🎯 Detected: GIF")
            else
                println("    ❓ Unknown image format")
            end
        end
        
        return true
        
    catch e
        println("    ❌ Base64 decode error: $e")
        return false
    end
end

debug_conv_jld2()