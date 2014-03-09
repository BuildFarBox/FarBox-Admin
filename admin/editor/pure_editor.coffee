posts_host = '/admin/editor/data'+location.search
sync_gateway = '/service/gateway/sync'
controls_width = 235


Post = (raw_post, editor) ->
    if raw_post.raw_path
        path_parts = raw_post.raw_path.split('/')
        @path = path_parts.slice(1).join('/')
    else
        @path = raw_post.path
    @title = ko.observable(raw_post.title)
    raw_content = raw_post['_content'] or ''
    title_reg = new RegExp('(?:^|([\r\n]))Title: ?'+ raw_post.title + ' *[\r\n]', 'i')
    @content = raw_content.replace(title_reg, '$1')

    @edit = =>
        # todo to sync
        # todo editor_model 是全局变量
        t_dom = $('#textarea')

        # 处理之前的post先
        if editor.current_post()
            editor.current_post()['content'] = t_dom.val()
            editor._sync(editor.get_path(), editor.get_content()) # 切换文章编辑的时候，先进行一次同步


        t_dom.val(@content)
        t_dom.focus()

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
        $.getJSON posts_host, {}, (posts)=>
            for post in posts
                @posts.push(new Post(post, self))
            # 进入编辑模式
            if @posts().length
                @posts()[0].edit()
            else
                @create_post()

    @create_post = =>
        paths = $.map @posts(), (post) -> post.path
        for i in [0..5]
            title = $.format.date(new Date(), 'yyyy-MM-dd')
            if i
                title = title + '-' + i
            path = title + '.txt'

            if $.inArray(path, paths) == -1  # 当前path不存在时, break, title有效
                break
            if i == 5
                return
        new_post = new Post({path: path, title: title}, self)
        @.posts.unshift(new_post)
        new_post.edit()



    @show_controls = ->
        if controls.position().left == -controls_width
            controls.animate({
                left: 0,
                opacity: 1
            }, 350, 'swing', make_textarea_center)
        if $.browser.msie
            $('#textarea').blur()

    @hide_controls = ->
        if controls.position().left == 0
            controls.animate({
                left: -controls_width,
                opacity: 0.3
            }, 500, 'swing', make_textarea_center)
            #setTimeout(make_textarea_center, 501)

        $('#textarea').focus()

    controls.mouseenter(@show_controls)


    @get_content = =>
        title = $.trim($('#title').val())
        title_value = 'Title: ' + title + '\n'
        raw_content = $.trim($('#textarea').val())
        if raw_content.match(/^\s*---\s*[\r\n]/)
            content = raw_content.replace(/^\s*---\s*[\r\n]/, '---\n'+title_value)
        else
            content = title_value + raw_content
        return content

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
            $('#textarea').focus()

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


    @insert_image_allowed = =>
        dom = $('#textarea')
        $(dom)[0].addEventListener  'drop', (event)=>
            files = event.dataTransfer.files

            for file in files
                if file.type.indexOf( 'image' ) == -1
                    continue

                reader = new FileReader()
                reader.readAsDataURL(file)
                reader.onload = (ev)=>
                    @upload_image(ev.target.result)
            event.preventDefault()
        , false

        $(dom)[0].addEventListener 'dragover', (event)->
            event.preventDefault()
        , false


    @canvas =  document.createElement( 'canvas' )
    @cx = @canvas.getContext('2d')

    @upload_image = (file)=>
        img = new Image()
        img.src = file

        # get the image data and upload to server
        $(img).one 'load', ->
            width = @naturalWidth or @width
            height = @naturalHeight or @height
            thumb_height = 2560
            thumb_width = 1280
            width_r = width/thumb_width
            height_r = height/thumb_height
            max_r = Math.max(width_r, height_r)
            w = if max_r>1 then width/max_r else width
            h = if max_r>1 then height/max_r else height

            self.canvas.width = w
            self.canvas.height = h
            self.cx.drawImage(this, 0, 0, w, h)

            image_path = '/_image' + $.format.date(new Date(), '/yyyy-MM-dd/HH-mm-ss') + '.jpg'

            request_data = {path: image_path, base64: self.canvas.toDataURL( 'image/jpeg' , 0.96)}

            Essage.show({message: 'Image Uploading, Wait or keep writing...', status: 'success'}, 30000)
            $.post sync_gateway, request_data, (resposne_data, status)->
                if status == 'success'
                    Essage.show({message: 'Image Uploaded, Done!', status: 'success'}, 5000)

            to_insert = '![Image]('+ image_path + ')\n'
            dom = $('#textarea')
            cursorPos = dom.prop('selectionStart')
            old_value = dom.val()
            text_before = old_value.substring(0,  cursorPos )
            text_after = old_value.substring(cursorPos, old_value.length)
            dom.val(text_before+to_insert+text_after)
            dom.focus()



    return this




make_textarea_center = ->
    # textarea width is 750
    # 用textarea作为主布局，可以综合body的滚动条
    dom = $('#textarea')
    title_dom = $('#title')
    textarea_width = 780
    padding = ($(document).width() - textarea_width)/2;
    controls = $('#controls')
    if controls.position().left == 0
        padding -= controls_width/2

    dom.css({"padding-right": padding+'px', 'width': textarea_width + padding + 'px'});
    title_dom.css({"right": padding+'px', 'width': textarea_width + 'px'})
    if $.browser.mozilla  #firefox
        dom.css({'width': textarea_width + 'px'})


@run_editor = =>
    editor_model = new EditorModel()
    @editor = editor_model
    window.onresize = make_textarea_center

    $(document).ready ->
        text_dom = $('#textarea')
        title_dom = $('#title')

        make_textarea_center()
        ko.applyBindings(editor_model)
        editor_model.load_posts()
        editor_model.insert_image_allowed()

        text_dom.scroll ->
            if text_dom.scrollTop() > 25
                title_dom.css('display', 'none')
            else
                title_dom.css('display', 'block')

        title_dom.keyup (event)->
            editor_model.current_post().title(title_dom.val())
            if event.which == 13
                text_dom.focus()

        window.onbeforeunload = =>
            if editor_model.need_sync()
                return 'Contents not saved yet, Please wait for a moment!'
            return null
