posts_host = '/admin/editor/data'+location.search
sync_gateway = '/service/gateway/sync'
controls_width = 235

@canvas_allowed = document.createElement('canvas').getContext


$.fn.shake = (options) ->
    selector = this
    settings = $.extend({'speed':100,'margin':20,'onComplete': false,'onStart':false},options)
    speed = settings['speed']
    margin = settings['margin']
    margin_total = parseInt(margin) + parseInt(margin)
    onComplete = settings['onComplete']
    onStart = settings['onStart']
    if onStart
        eval(onStart)
    $(selector).animate {marginLeft:margin}, speed/2, ->
        $(selector).animate {marginLeft:'-'+margin_total}, speed, ->
            $(selector).animate {marginLeft:''+margin_total},speed, ->
                $(selector).animate {marginLeft:'-'+margin_total},speed, ->
                    $(selector).animate {marginLeft:''+margin_total},speed, ->
                        $(selector).animate {marginLeft:'-'+margin_total},speed, ->
                            $(selector).animate {marginLeft:'-0'},speed, ->
                                if onComplete
                                    eval(onComplete)




Post = (raw_post, editor) ->
    if raw_post.raw_path
        path_parts = raw_post.raw_path.split('/')
        @path = path_parts.slice(1).join('/')
    else
        @path = raw_post.path
    @title = ko.observable(raw_post.title)
    raw_content = raw_post['_content'] or ''
    prereged_title = raw_post.title
    for c in ['$','\\','{','}','[',']','(',')','^','.','*','+','?','|']
        prereged_title = prereged_title.replace(c,'\\'+c)
    title_reg = new RegExp('(?:^|([\r\n]))Title: ?'+ prereged_title + ' *[\r\n]', 'i')
    @content = raw_content.replace(title_reg, '$1')

    @edit = =>
        # todo to sync
        # todo editor_model 是全局变量
        t_dom = $('#textarea')

        # 处理之前的post先
        if editor.current_post()
            editor.current_post()['content'] = t_dom.val()
            editor._sync(editor.get_path(), editor.get_content()) # 切换文章编辑的时候，先进行一次同步

        if not $.trim(@content)
            # 填充时间戳
            @content = 'Date: ' + $.format.date(new Date(), 'yyyy-MM-dd HH:mm')  + '\n\n'
            to_tail = true
        else
            to_tail = false

        t_dom.val(@content)
        t_dom.focus()

        if to_tail
            @to_text_tail()
        else
            @to_text_first_line_end()

        $('#posts li a.current').removeClass('current')
        index = $.inArray(this, editor.posts())
        current_post_dom = $($('#posts li a')[index])
        current_post_dom.addClass('current')
        editor.current_post(this)

    @to_text_tail = ->
        obj = $('#textarea')[0]
        obj.selectionStart = obj.selectionEnd = obj.value.length

    @to_text_first_line_end = ->
        obj = $('#textarea')[0]
        if obj.value.indexOf('\n')
            obj.selectionStart = obj.selectionEnd = obj.value.indexOf('\n')
        else
            obj.selectionStart = obj.selectionEnd = obj.value.length

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
                @create_first_post()

    @create_first_post = =>
        title = $.format.date(new Date(), 'yyyy-MM-dd')
        path = title + '.txt'
        new_post = new Post({path: path, title: title}, self)
        @.posts.unshift(new_post)
        new_post.edit()


    @open_new_window = ->
        $('#new_window').css('display', 'block')
        $('#window_bg').css('background', '#000')
        $('#window_bg').css('opacity', '0.6')
        $('#new_window input').val('')
        $('#new_window input').focus()

    @hide_new_window = ->
        $('#new_window').css('display', 'none')

    @create_new_one = =>
        new_path = $.trim($('#new_path').val())
        if new_path
            if not new_path.match(/\.(md|markdown|txt|mk)$/gi)
                new_path = new_path+'.txt'
            paths = $.map @posts(), (post) -> post.path
            if $.inArray(new_path, paths) == -1
                title = new_path.replace(/\.(md|markdown|txt|mk)$/gi, '')
                new_post = new Post({path: new_path, title: title}, self)
                @.posts.unshift(new_post)
                new_post.edit()
                @hide_new_window()
            else
                $('#new_window_body').shake()
        else
            $('#new_window_body').shake()
        $('#new_window input').focus()

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
        if not @canvas_allowed
            return false
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
    if @canvas_allowed
        @cx = @canvas.getContext('2d')
    else
        @cx = null

    @upload_image = (file)=>
        if not @canvas_allowed
            return false

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

realtime_input = (editor_model)->
    if WebSocket? and JSON?
        if document.location.protocol == 'https:' then ws_protocl='wss:' else ws_protocl='ws:'
        ws_url = ws_protocl+'realtime.farbox.com/notes'
        socket = null
        connect_to_farbox = =>
            socket = new WebSocket(ws_url)
            connectted_at = new Date()
            socket.onmessage = (message)->
                note = JSON.parse(message.data)
                if note.path == editor_model.current_post().path
                    $.get '/admin/editor/appended/~~'+note.path, {}, (data)->
                        if data
                            text_dom = $('#textarea')
                            text_dom.val(text_dom.val()+'\n\n'+data)
            socket.onclose = ->
                if (new Date() - connectted_at)/1000 > 10
                    connect_to_farbox() #reconnect
        keep_live = =>
            if socket
                socket.send('ping')
        # first time call
        connect_to_farbox()
        setInterval(keep_live, 30000)

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

        realtime_input(editor_model)



