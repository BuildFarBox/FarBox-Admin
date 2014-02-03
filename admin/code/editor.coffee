data_host = '/admin/code/data'
sync_gateway = '/service/gateway/sync'
controls_width = 235


Post = (raw_post, editor) ->
    @path = raw_post.path
    @title = raw_post.path.split('/').slice(1).join('/')
    @content = raw_post['content'] or ''

    @edit = =>
        # todo to sync
        # todo editor_model 是全局变量
        # 处理之前的post先
        if editor.current_post()
            editor.current_post()['content'] = editor.get_content()
            editor._sync(editor.get_path(), editor.get_content()) # 切换文章编辑的时候，先进行一次同步

        $('#editor CodeMirror').remove()

        indent_with_tab = false
        if raw_post.ext == 'jade'
            if not @content
                indent_with_tab = true
            else if @content.match(/(^|\n)\t/)
                indent_with_tab = true
            mode = {name: "jade", alignCDATA: true}
        else if raw_post.ext == 'html'
            mode = {name: "jinja2", htmlMode: true}
        else if raw_post.ext == 'js'
            mode = 'javascript'
        else if raw_post.ext == 'less'
            mode = "text/x-less"
        else if raw_post.ext in ['sass', 'scss']
            mode = "text/x-scss"
        else if raw_post.ext == 'css'
            mode = 'text/css'


        @code_editor = CodeMirror(document.getElementById("editor"), {
            value: @content,
            lineNumbers: true,
            matchBrackets : true,
            mode: mode,
            theme: 'solarized',
            indentWithTabs: indent_with_tab,
        })

        @code_editor.focus()

        @doc = @code_editor.getDoc()
        @doc.on 'change', (the_doc, change_obj)=>
            editor.sync()

        # for sidebar
        $('#posts li a.current').removeClass('current')
        index = $.inArray(this, editor.posts())
        current_post_dom = $($('#posts li a')[index])
        current_post_dom.addClass('current')

        editor.current_post(this)

    @remove = =>
        # todo 发送删除的
        $.post sync_gateway, {'path': @path, 'is_deleted': true}
        editor.posts.remove(this)
        if editor.posts().length
            if @path == editor.get_path() # 删除了当前的post，需要focus到第一篇
                current = editor.posts()[0]
                current.edit()
        else
            editor.create_post()

    return this


EditorModel = ->
    self = this
    controls = $('#controls')
    @posts = ko.observableArray([])
    @current_post = ko.observable({})
    @current_title = ko.observable('')
    @need_sync = ko.observable(false)
    @sync_per_seconds = 20 # 20秒同步一次

    @show_tip_info = ko.observable(false)
    @tip_info = ko.observable('Save')
    @wait_to_sync_precess = ko.observable(0)


    @load_posts = =>
        # load the posts data
        $.getJSON data_host, {}, (posts)=>
            for post in posts
                @posts.push(new Post(post, self))
            # 进入编辑模式
            if @posts().length
                @posts()[0].edit()
            else
                @create_post()

    @create_post = =>
        paths = $.map @posts(), (post) -> post.path
        path = window.prompt("Path:","")
        if path in paths
            Essage.show({message: 'this path already exists', status: 'error'})
            return false # ignore
        else
            ext_parts = path.split('.')
            ext = ext_parts[ext_parts.length-1]
            if ext not in ['scss', 'sass', 'css', 'less', 'jade', 'html']
                Essage.show({message: 'this file type is not allowed', status: 'error'})
                return false
            path = path.replace(/^\//g, '', path)
            new_post = new Post({path: 'template/' + path, ext: ext}, self)
            @.posts.unshift(new_post)
            new_post.edit()


    @get_content = =>
        code_editor_doc = @current_post().doc
        if code_editor_doc
            return code_editor_doc.getValue()
        else
            return ''

    @get_path = =>
        return @current_post().path

    @sync = =>
        # 第一次按键，初始化
        if not @keep_sync_binded
            @keep_sync_binded = true
            setInterval(@keep_sync, 1000) # 键盘闲置1秒的时候，检测
            @last_sync_at = new Date()
            @need_sync(true)

        if not @need_sync() # 计时重置
            @last_sync_at = new Date()

        @need_sync(true)
        @show_tip_info(true)

        diff_seconds = @sync_per_seconds - (new Date() - @last_sync_at)/1000
        @wait_to_sync_precess(100*(1-diff_seconds/@sync_per_seconds)+'%')

        if diff_seconds > 0
            return false # ignore
        else
            @_sync()

    @keep_sync = =>
        if not @need_sync()
            return false
        else
            @sync()


    @_sync = (path, content)=>
        if typeof(path) != 'string'
            path = ''
        if typeof(content) != 'string'
            content = ''

        if not @need_sync()
            return false # ignore
        else
            @last_sync_at = new Date()
            @need_sync(false) # reset

        @tip_info('Saving...')
        path = path or @get_path()
        content = content or @get_content()
        data = {
            path: path,
            raw_content: content
        }
        $.post sync_gateway, data, =>
            @tip_info('Save')
            if not @need_sync()
                @show_tip_info(false)


    return this


@run_editor = =>
    editor_model = new EditorModel()
    @editor = editor_model

    $(document).ready ->
        ko.applyBindings(editor_model)
        editor_model.load_posts()

        window.onbeforeunload = =>
            if editor_model.need_sync()
                return 'Contents not saved yet, Please wait for a moment!'
            return null
