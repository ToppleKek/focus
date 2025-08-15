init_decl_finder :: () {
    num_cpus := get_num_cpus();
    num_threads := max(num_cpus - 1, 1);

    thread_group = Thread_Group.{};
    init(*thread_group, num_threads, group_proc = search_threadproc);
    thread_group.name = "Decl Finder";
    thread_group.logging = false;
    for * thread_group.worker_info { it.thread.starting_context.logger_data = context.logger_data; }

    start(*thread_group);

    decl_finder.initted = true;
}

deinit_decl_finder :: () {
    if decl_finder.initted shutdown(*thread_group);
    reset_results();
    text_input_fully_clear(*decl_finder.input);
    decl_finder.initted = false;
}

decl_finder_handle_event :: (event: Input.Event) -> handled: bool {
    using decl_finder;

    if event.type == .KEYBOARD && event.key_pressed {
        handled := text_input_handle_event(*input, event);
        if handled { start_new_search(); return true; }

        action, mapping := map_event_to_action(event, Action_Search_Dialog);
        if action == {
            case .toggle_expand;            toggle_expand();                                        return true;

            case .move_up;                  move_cursor(-1, wrap = true);                           return true;
            case .move_down;                move_cursor( 1, wrap = true);                           return true;
            case .move_up_fast;             move_cursor(-5);                                        return true;
            case .move_down_fast;           move_cursor( 5);                                        return true;
            case .move_up_one_page;         move_cursor(-per_page);                                 return true;
            case .move_down_one_page;       move_cursor( per_page);                                 return true;

            case .escape;                     #through;
            case .close_dialog;               decl_finder_close();                                  return true;

            case .open_entry;               decl_finder_open_selected_result(.in_place);            return true;
            case .open_entry_in_side_pane;  decl_finder_open_selected_result(.on_the_side);         return true;

            case .switch_to_left_pane;      decl_finder_open_selected_result(.left);                return true;
            case .switch_to_right_pane;     decl_finder_open_selected_result(.right);               return true;
            case .switch_to_top_pane;       decl_finder_open_selected_result(.top);                 return true;
            case .switch_to_bottom_pane;    decl_finder_open_selected_result(.bottom);              return true;

            case .switch_to_pane_1;         decl_finder_open_selected_result_in_pane(1);            return true;
            case .switch_to_pane_2;         decl_finder_open_selected_result_in_pane(2);            return true;
            case .switch_to_pane_3;         decl_finder_open_selected_result_in_pane(3);            return true;
            case .switch_to_pane_4;         decl_finder_open_selected_result_in_pane(4);            return true;
            case .switch_to_pane_5;         decl_finder_open_selected_result_in_pane(5);            return true;
            case .switch_to_pane_6;         decl_finder_open_selected_result_in_pane(6);            return true;
            case .switch_to_pane_7;         decl_finder_open_selected_result_in_pane(7);            return true;
            case .switch_to_pane_8;         decl_finder_open_selected_result_in_pane(8);            return true;
            case .switch_to_pane_9;         decl_finder_open_selected_result_in_pane(9);            return true;
        }
        return false;

    } else if event.type == .TEXT_INPUT {
        text_input_type_char(*input, event.utf32);
        start_new_search();
        return true;
    }
    return false;
}

decl_finder_is_open :: () -> bool {
    return active_global_widget == .decl_finder;
}

decl_finder_open :: () {
    active_global_widget = .decl_finder;

    using decl_finder;
    input.cursor.sel = 0;
    input.cursor.pos = xx input.text.count;

    // case_sensitive_toggled_manually = false;

    if need_to_refresh_results {
        need_to_refresh_results = false;
        reset_results();
        start_new_search(force = true);
    }
}

decl_finder_close :: () {
    activate_editors();
}

// finder_activate_input :: inline (input: Finder.Active_Input) {
//     finder.active_input = input;
// }

// finder_go_to_next_input :: () {
//     NUM_INPUTS :: #run enum_highest_value(Finder.Active_Input) + 1;
//     next_input := (cast(u32) finder.active_input + 1) % NUM_INPUTS;
//     finder_activate_input(cast(Finder.Active_Input) next_input);
// }

// finder_go_to_previous_input :: () {
//     NUM_INPUTS :: #run enum_highest_value(Finder.Active_Input) + 1;
//     current_input := cast(u32) finder.active_input;
//     next_input := ifx current_input == 0 then NUM_INPUTS - 1 else current_input - 1;
//     finder_activate_input(cast(Finder.Active_Input) next_input);
// }

// NOTE: Sets the input text to be whatever was selected before opening the widget.
decl_finder_open_from_editor :: () {
    editor, buffer := get_active_editor_and_buffer();

    // If there was some text selected that doesn't span more than one line, use it for search
    if editor && editor.cursors.count == 1 {
        cursor := editor.cursors[0];
        selected_text := get_selected_string(cursor, buffer);
        if selected_text && selected_text != to_string(decl_finder.input.text) && offset_to_line(editor, buffer, cursor.pos) == offset_to_line(editor, buffer, cursor.sel) {
            replace_text(*decl_finder.input, selected_text);
            reset_results();
            start_new_search();
        }
    }

    decl_finder_open();
}

decl_finder_update :: () {
    // using decl_finder;
    if !decl_finder.initted return;

    // If a buffer has changed while we have the finder window open, we have to refresh
    if decl_finder_is_open() && decl_finder.need_to_refresh_results {
        decl_finder.need_to_refresh_results = false;
        reset_results();
        start_new_search(force = true);
    }

    tasks := get_completed_work(*thread_group);
    for tasks {
        task := it.(*Decl_Finder_Search_Task);

        if task.request_id != decl_finder.request.id {
            // This is a task from a previous request, free it and move on.
            log("Ignoring and freeing task from a previous request.");
            free(task);
            continue;
        }

        if task.task_id < 0 {
            log("SKIPPING ALREADY COMPLETED TASK");
            continue;
        }

        decl_finder.results[task.task_id] = task.result;
        task.task_id = -1;
        array_add(*decl_finder.request.completed_tasks, task);
        decl_finder.results_found += 1;
    }

    if decl_finder.results_found == decl_finder.results.count {
        decl_finder.results_ready = true;
        redraw_requested = true;
        // log("Results are ready from decl finder");
    }

    assert(decl_finder.results_found <= decl_finder.results.count);

    // for tasks {
        // task := cast(*Search_Task) it;

        // if request.id != task.request_id {
        //     // Old task, ignore
        //     free_task(task);
        //     continue;
        // }

        // if task.worker_limit_reached then finder.result_limit_reached = true;

        // array_add(*request.completed_tasks, task);
        // request.num_tasks_left -= 1;
        // if request.num_tasks_left == 0 {
        //     // Received all data, collect all results for displaying
        //     total_results := 0;
        //     for request.completed_tasks total_results += it.num_results;
        //     array_resize(*results, total_results, initialize = false);
        //     i := 0;
        //     for request.completed_tasks {
        //         focus_memcpy(results.data + i, it.results.data, it.num_results * size_of(Search_Result));
        //         i += it.num_results;
        //     }

        //     compare_search_results :: (r1: Search_Result, r2: Search_Result) -> s64 {
        //         return cast,no_check(s64) r1.sort_key - cast,no_check(s64) r2.sort_key;
        //     }

        //     quick_sort(results, compare_search_results);

        //     if needle then free(needle);
        //     needle = copy_string(request.needle);

        //     // Clean up task data
        //     for request.completed_tasks free_task(it);
        //     array_reset_keeping_memory(*request.completed_tasks);

        //     scroll_y = 0;
        //     scroll_anim.target = 0;
        //     selected = 0;
        //     request.in_progress = false;
        // }
    // }

    // if decl_finder.results_ready then redraw_requested = true;
}

decl_finder_open_selected_result :: (placement: Editor_Placement, selected_num := -1) {
    using decl_finder;

    // results := resulting_ctags.*;
    // if request.in_progress return;
    if selected_num >= 0 then selected = selected_num;
    if selected >= results.count return;

    result := results[selected];
    // TODO: @Incomplete.
    editors_open_buffer(result.buffer_id, placement);
    decl_finder_jump_to_search_result(result);
}

decl_finder_open_selected_result_in_pane :: (number: s64) {
    target_pane := editors_find_pane_by_number(number);
    if !target_pane {
        add_user_error("Pane number % doesn't exist", number, dismiss_in_seconds = 3);
        return;
    }

    result := decl_finder.results[decl_finder.selected];
    editors_open_buffer_in_pane(result.buffer_id, target_pane);
    decl_finder_jump_to_search_result(result);
}

decl_finder_jump_to_search_result :: (result: Decl_Finder_Search_Result) {
    activate_editors();
    editor, buffer := get_active_editor_and_buffer();
    match_start := min(result.match_offset,                      xx buffer.bytes.count);  // buffer could've changed, so offset may not be valid any more
    match_end   := min(result.match_offset + result.match_count, xx buffer.bytes.count);
    cursor := leave_only_original_cursor(editor);
    cursor.sel = xx match_start;
    cursor.pos = xx match_end;

    editor.scroll_to_cursor = .yes;
}

#scope_file

move_cursor :: (delta: s64, wrap := false, snap := true) {
    using decl_finder;

    selected += delta;

    if wrap {
        if selected < 0 then selected = max(0, results.count - 1);
        if selected >= results.count then selected = 0;
    } else {
        if selected < 0 then selected = 0;
        if selected >= results.count then selected = results.count - 1;
    }
    scroll_to_cursor = ifx snap then Scroll_Mode.snap else .yes;
}

start_new_search :: (force := false) {
    using decl_finder;

    if !initted return;

    decl_to_lookup := to_string(input.text);

    if !decl_to_lookup {
        reset_search_request(*request);
        reset_results();
        return;
    }

    ctags := lookup_ctags(decl_to_lookup);

    results_found = 0;
    array_reset_keeping_memory(*results);

    if !ctags {
        results_ready = true;
        return;
    }

    array_resize(*results, ctags.count);
    results_ready = false;
    // if needle then free(needle); // TODO: @Incomplete.
    // needle = copy_string(new_needle);

    // if !force && request.needle == new_needle then return;  // Nothing has changed, no need to repeat.

    // request.case_sensitive = case_sensitive; // TODO: Do we care about case senstivity in this?

    reset_search_request(*request);
    request.in_progress = true;

    num_threads := thread_group.worker_info.count;
    assert(num_threads > 0);

    for * (ctags.*) {
        task := New(Decl_Finder_Search_Task);
        task.task_id = it_index;
        task.request_id = request.id;
        task.ctag    = it;
        add_work(*thread_group, task);
    }

    // while buffer_start_index < open_buffers.count {
    //     task := New(Search_Task);
    //     task.request_id = request.id;
    //     task.needle  = copy_string(request.needle);  // we have to copy because otherwise we'd have to sync with other threads
    //     task.include = copy_string(request.include);
    //     task.exclude = copy_string(request.exclude);
    //     task.skip_table = array_copy(request.skip_table);
    //     task.buffer_start_index = cast(s32) buffer_start_index;
    //     task.buffer_end_index   = cast(s32) min(buffer_start_index + buffers_per_task - 1, open_buffers.count - 1);
    //     task.case_sensitive = request.case_sensitive;
    //     task.whole_word = request.whole_word;
    //     task.regex_search = request.regex_search;

    //     add_work(*thread_group, task, needle);
    //     request.num_tasks_left += 1;  // only modified in the main thread so no atomics needed

    //     buffer_start_index += buffers_per_task;
    // }
}

search_threadproc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    // if !ctags_scan_complete {
    //     return .CONTINUE; // TODO: IDK!!
    // }
    reset_temporary_storage();

    task := (work.(*Decl_Finder_Search_Task));

    assert(task.task_id != -1);
    assert(task.task_id < 9999);

    full_path := join(task.ctag.base_path, task.ctag.file,, temp);
    path      := parse_path(full_path, reduce = true);

    buffer_id, created := find_or_create_buffer(path_to_string(path,, temp)); // FIXME: @Incomplete. Got a memory error here from the memory debugger... On copy string in this function... Perhaps there is something to lock...
    buffer := *open_buffers[buffer_id];

    task.result.buffer_id = buffer_id.(s32);
    task.result.match_offset = find_index_from_left(to_string(buffer.bytes), task.ctag.address).(s32); // TODO: @Incomplete @Myfork do a real search here.
    task.result.match_count = task.ctag.address.count.(s32);

    // The file could have been edited the last time we generated ctags...
    if task.result.match_offset == -1 {
        task.result.match_offset = 0;
        task.result.match_count  = 1;
    }

    // decl_finder.resulting_ctags = lookup_ctags(decl_finder.needle);
    return .CONTINUE;  // we want to reuse this thread for future searches
}

reset_search_request :: (using request: *Decl_Finder_Search_Request) {
    id += 1;
    for completed_tasks free(it);
    array_reset_keeping_memory(*completed_tasks);

    // num_tasks_left = 0;
    in_progress = false;
    decl_finder.result_limit_reached = false;
}

reset_results :: () {
    using decl_finder;
    // if needle then free(needle);
    // needle = "";
    results_found = 0;
    results_ready = false;
    result_limit_reached = false;
    // resulting_ctags = null; // NOTE: The search results are just a pointer into the ctags table...
    array_reset_keeping_memory(*results);
    scroll_y = 0;
    scroll_anim.target = 0;
    selected = 0;
}

toggle_expand :: () {
    using decl_finder;

    target_width := ifx width_percentage != WIDTH_EXPANDED then WIDTH_EXPANDED else WIDTH_NORMAL;
    start_animation(*width_anim, width_percentage, target_width);
}

#scope_export

decl_finder: Decl_Finder;

Decl_Finder :: struct {
    initted := false;  // will be initialized when the initial workspace scan completes

    input: Text_Input;

    request: Decl_Finder_Search_Request;
    needle: string;  // to remember what search string the results below correspond to
    // resulting_ctags: *[..] Ctag;
    results: [..] Decl_Finder_Search_Result;
    result_limit_reached: bool;
    results_found: s64;
    results_ready: bool;

    selected: s64;
    selected_by_mouse: s64 = -1;  // to remember which entry the left mouse button went down on. Do we need it?
    per_page := 10;

    scroll_y: s32;
    scroll_anim := #run Tween_Animation(s32).{ duration = 0.1, func = .lerp };
    scroll_to_cursor: Scroll_Mode = .no;

    width_percentage := WIDTH_NORMAL;  // how much of the screen the popup occupies
    width_anim := #run Tween_Animation(float).{ start = WIDTH_NORMAL, target = WIDTH_NORMAL };
    WIDTH_NORMAL   :: 0.7;
    WIDTH_EXPANDED :: 0.95;

    // search_input_width  := 0.7;  // how much of the total width is allocated for the search input
    // include_input_width := 0.5;  // splitter position between the filter inputs

    need_to_refresh_results: bool;  // when a buffer is modified and we have some search results, we have to search again,
                                    // otherwise the search results may point to an offset which no longer exists or is invalid
}

#scope_file

Decl_Finder_Search_Result :: struct {
    // Line numbers and boundaries will be calculated at draw time only for the visible entries
    // as they require doing an additional search in buffer.
    buffer_id:    s32;
    match_offset: s32;
    match_count:  s32;
    // sort_key:     u64;
}

Decl_Finder_Search_Task :: struct {
    task_id: s64;
    request_id: s64;
    ctag: *Ctag;
    result: Decl_Finder_Search_Result;
}

// When we start a new search, a new request it created, and all the results from
// any unfinished tasks from a previous search will be discarded when they arrive
Decl_Finder_Search_Request :: struct {
    id: s64 = -1;
    // num_tasks_left: s32;
    completed_tasks: [..] *Decl_Finder_Search_Task;
    in_progress: bool;
}

// A task received by a worker thread
// Search_Task :: struct {
//     request_id:  s64;
//     needle: string;
//     skip_table: [] s32;

//     // To be filled by the worker thread
//     num_results: s64;
//     results: [MAX_RESULTS_PER_TASK] Search_Result;
//     worker_limit_reached: bool;
// }

// in_progress_tasks: [..] Decl_Finder_Search_Task;
// completed_tasks: [..] *Decl_Finder_Search_Task;
thread_group: Thread_Group;

// MAX_RESULTS_PER_TASK :: 16;
