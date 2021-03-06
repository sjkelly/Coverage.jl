#######################################################################
# Coverage.jl
# Take Julia test coverage results and bundle them up in JSONs
# https://github.com/IainNZ/Coverage.jl
#######################################################################
module Coverage

    # process_cov
    # Given a .cov file, return the counts for each line, where the
    # lines that can't be counted are denoted with a -1
    export process_cov
    function process_cov(filename)
        fp = open(filename, "r")
        lines = readlines(fp)
        num_lines = length(lines)
        coverage = Array(Union(Nothing,Int), num_lines)
        for i = 1:num_lines
            cov_segment = lines[i][1:9]
            coverage[i] = cov_segment[9] == '-' ? nothing : int(cov_segment)
        end
        close(fp)
        return coverage
    end

    export Coveralls
    module Coveralls
        using Requests
        using Coverage
        using JSON

        # coveralls_process_file
        # Given a .jl file, return the Coveralls.io dictionary for this
        # file by reading in the file and its matching .cov. Don't convert
        # to JSON yet, just return dictionary.
        # https://coveralls.io/docs/api
        # {
        #   "name" : "$filename"
        #   "source": "...\n....\n...."
        #   "coverage": [null, 1, null]
        # }
        export process_file
        function process_file(filename)
            return ["name" => filename,
                    "source" => readall(filename),
                    "coverage" => process_cov(filename*".cov")]
        end

        # coveralls_process_src
        # Recursively walk through a Julia package's src/ folder
        # and collect coverage statistics
        export process_folder
        function process_folder(folder="src")
            source_files={}
            filelist = readdir(folder)
            for file in filelist
                fullfile = joinpath(folder,file)
                println(fullfile)
                if isfile(fullfile)
                    try
                        new_sf = process_file(fullfile)
                        push!(source_files, new_sf)
                    catch e
                        if !isa(e,SystemError)
                            rethrow(e)
                        end
                        # Skip
                        println("Skipped $fullfile")
                    end
                else isdir(fullfile)
                    append!(source_files, process_folder(fullfile))
                end
            end
            return source_files
        end

        # submit
        # Submit coverage to Coveralls.io
        # https://coveralls.io/docs/api
        # {
        #   "service_job_id": "1234567890",
        #   "service_name": "travis-ci",
        #   "source_files": [
        #     {
        #       "name": "example.rb",
        #       "source": "def four\n  4\nend",
        #       "coverage": [null, 1, null]
        #     },
        #     {
        #       "name": "lib/two.rb",
        #       "source": "def seven\n  eight\n  nine\nend",
        #       "coverage": [null, 1, 0, null]
        #     }
        #   ]
        # }
        export submit, submit_token
        function submit(source_files)
            data = ["service_job_id" => ENV["TRAVIS_JOB_ID"],
                    "service_name" => "travis-ci",
                    "source_files" => source_files]
            r = Requests.post(URI("https://coveralls.io/api/v1/jobs"), files =
                [FileParam(JSON.json(data),"application/json","json_file","coverage.json")])
            dump(r.data)
        end

        function submit_token(source_files)
            data = ["repo_token" => ENV["REPO_TOKEN"],
                    "source_files" => source_files]
            r = post(URI("https://coveralls.io/api/v1/jobs"), files =
                [FileParam(JSON.json(data),"application/json","json_file","coverage.json")])
            dump(r.data)
        end
    end  # module Coveralls


    ## Analyzing memory allocation
    immutable MallocInfo
        bytes::Int
        filename::UTF8String
        linenumber::Int
    end

    sortbybytes(a::MallocInfo, b::MallocInfo) = a.bytes < b.bytes

    function analyze_malloc_files(files)
        bc = MallocInfo[]
        for filename in files
            open(filename) do file
                for (i,ln) in enumerate(eachline(file))
                    tln = strip(ln)
                    if !isempty(tln) && isdigit(tln[1])
                        s = split(tln)
                        b = parseint(s[1])
                        push!(bc, MallocInfo(b, filename, i))
                    end
                end
            end
        end
        sort(bc, lt=sortbybytes)
    end

    function find_malloc_files(dirs)
        files = ByteString[]
        for dir in dirs
            filelist = readdir(dir)
            for file in filelist
                file = joinpath(dir, file)
                if isdir(file)
                    append!(files, find_malloc_files(file))
                elseif endswith(file, "jl.mem")
                    push!(files, file)
                end
            end
        end
        files
    end
    find_malloc_files(file::ByteString) = find_malloc_files([file])

    analyze_malloc(dirs) = analyze_malloc_files(find_malloc_files(dirs))
    analyze_malloc(dir::ByteString) = analyze_malloc([dir])

    # Support Unix command line usage like `julia Coverage.jl $(find ~/.julia/v0.3 -name "*.jl.mem")`
    if !isinteractive()
        bc = analyze_malloc_files(ARGS)
        println(bc)
    end
end
