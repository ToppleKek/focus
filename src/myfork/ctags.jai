Ctag :: struct {
    name: string;
    file: string;
    address: string;
    base_path: string; // NOTE: This string is stored in an array to save copying the same base path for every single entry in one ctags file. Do not free it!
}

lookup_ctags :: (ident: string) -> *[..] Ctag {
    // print("CTAGS: Looking up: %\n", ident);
    return table_find_pointer(*all_tags, ident);
}

async_load_ctag_files :: (paths: [] string) {
    if !is_all_loaded {
        should_kill_loader_thread = true;
        // thread join, free existing loader_thread_data, etc.
        // @MyFork @Incomplete
    } else {
        is_all_loaded             = false;
        should_kill_loader_thread = false;

        loader_thread_data := array_copy(paths);
        thread_init(*loader_thread, async_load_ctag_files_thread_proc);
    }
}

clear_all_ctags :: () {
    table_reset(*all_tags);
    deinit(*all_tags);
    is_all_loaded = true;
}

#scope_file

all_tags: Table(string, [..] Ctag);
base_paths: [..] string;
loader_thread: Thread;
loader_thread_data: [] string;
is_all_loaded := true;
should_kill_loader_thread := false;

async_load_ctag_files_thread_proc :: (thread: *Thread) -> s64 {
    assert(!is_all_loaded);
    for loader_thread_data load_ctag_file(it);
    is_all_loaded = true;
    array_reset(*loader_thread_data);
    return 0;
}

load_ctag_file :: (path: string) {
    print("CTAGS: Loading %\n", path);
    handler: Text_File_Handler;
    defer deinit(*handler);

    handler.do_version_number                 = false;
    handler.auto_skip_blank_lines             = false;
    handler.strip_comments_from_ends_of_lines = false;

    start_file(*handler, "", path);
    assert(!handler.failed);

    base_path: string;

    loaded := 0;
    while true {
        line, found := consume_next_line(*handler);
        if !found || !line then break;

        if line[0] == #char "!" && !base_path {
            parts := split(line, "\t",, temp);

            if parts[0] == "!_TAG_PROC_CWD" {
                assert(parts.count > 1);
                found, index := array_find(base_paths, parts[1]);
                if found {
                    base_path = base_paths[index];
                } else {
                    s := copy_string(parts[1]);
                    array_add(*base_paths, s);
                    base_path = s;
                }
            }

            continue;
        }

        assert(base_path.count != 0);

        success, tag := parse_one_ctag(line, base_path);
        if success {
            // array_add(*all_tags_array, tag);
            existing_tags := table_find_pointer(*all_tags, tag.name);
            if existing_tags {
                array_add(existing_tags, tag);
            } else {
                new_tags: [..] Ctag;
                array_add(*new_tags, tag);
                table_add(*all_tags, tag.name, new_tags);
            }

            loaded += 1;
        }

        // if loaded % 1000 == 0 then print("Loaded % tags\n", loaded);
    }
}

parse_one_ctag :: (line: string, base_path: string) -> bool, Ctag {
    ret: Ctag;

    if line[0] == #char "!" then return false, .{};

    found, left, right := split_from_left(line, #char "\t");
    if !found then return false, .{};

    ret.name = copy_string(left);

    found, left, right = split_from_left(right, #char "\t");
    if !found then return false, .{};

    ret.file = copy_string(left);

    found, left, right = split_from_left(right, "/;\"");
    if !found then return false, .{};

    if left[0] == #char "/" {
        left.data += 1;
        left.count -= 1;
    }

    if left[0] == #char "^" {
        left.data += 1;
        left.count -= 1;
    }

    if ends_with(left, #char "$") then left.count -= 1; // FIXME: Perhaps this might be a real $... Maybe...

    ret.address   = copy_string(left);
    ret.base_path = base_path;

    assert(0 != ret.name.count);
    assert(0 != ret.file.count);
    assert(0 != ret.address.count);
    assert(0 != ret.base_path.count);

    return true, ret;
}

#import "Hash_Table";
#import "Text_File_Handler";
#import "Basic";
#import "String";