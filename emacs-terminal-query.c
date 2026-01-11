#include <emacs-module.h>
#include <termios.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>

int plugin_is_GPL_compatible;

// 查询光标位置（行、列）
static emacs_value
terminal_query_cursor_position(emacs_env *env, ptrdiff_t nargs,
                               emacs_value args[], void *data) {
    int fd = open("/dev/tty", O_RDWR | O_NOCTTY);
    if (fd < 0) {
        return env->intern(env, "nil");
    }
    
    struct termios old_tio, new_tio;
    tcgetattr(fd, &old_tio);
    new_tio = old_tio;
    new_tio.c_lflag &= ~(ICANON | ECHO);
    new_tio.c_cc[VMIN] = 0;
    new_tio.c_cc[VTIME] = 5;
    tcsetattr(fd, TCSANOW, &new_tio);
    
    // 发送 CPR (Cursor Position Report) 查询
    write(fd, "\033[6n", 4);
    
    usleep(100000);
    char buf[64] = {0};
    int n = read(fd, buf, sizeof(buf) - 1);
    
    tcsetattr(fd, TCSANOW, &old_tio);
    close(fd);
    
    if (n <= 0) {
        return env->intern(env, "nil");
    }
    
    // 解析 ESC[row;colR
    int row, col;
    if (sscanf(buf, "\033[%d;%dR", &row, &col) == 2) {
        emacs_value result[2];
        result[0] = env->make_integer(env, row);
        result[1] = env->make_integer(env, col);
        return env->funcall(env, env->intern(env, "cons"), 2, result);
    }
    
    return env->intern(env, "nil");
}

// 查询字符像素大小
static emacs_value
terminal_query_cell_size(emacs_env *env, ptrdiff_t nargs,
                        emacs_value args[], void *data) {
    int fd = open("/dev/tty", O_RDWR | O_NOCTTY);
    if (fd < 0) {
        return env->intern(env, "nil");
    }
    
    struct termios old_tio, new_tio;
    tcgetattr(fd, &old_tio);
    new_tio = old_tio;
    new_tio.c_lflag &= ~(ICANON | ECHO);
    new_tio.c_cc[VMIN] = 0;
    new_tio.c_cc[VTIME] = 5;
    tcsetattr(fd, TCSANOW, &new_tio);
    
    write(fd, "\033[16t", 5);
    usleep(100000);
    char buf[64] = {0};
    int n = read(fd, buf, sizeof(buf) - 1);
    
    tcsetattr(fd, TCSANOW, &old_tio);
    close(fd);
    
    int type, height, width;
    if (n > 0 && sscanf(buf, "\033[%d;%d;%dt", &type, &height, &width) == 3 && type == 6) {
        emacs_value result[2];
        result[0] = env->make_integer(env, width);
        result[1] = env->make_integer(env, height);
        return env->funcall(env, env->intern(env, "cons"), 2, result);
    }
    
    return env->intern(env, "nil");
}

int emacs_module_init(struct emacs_runtime *ert) {
    emacs_env *env = ert->get_environment(ert);
    emacs_value fset = env->intern(env, "fset");
    emacs_value args[2];
    
    // 注册光标位置查询
    args[0] = env->intern(env, "terminal-query-cursor-position");
    args[1] = env->make_function(env, 0, 0, terminal_query_cursor_position,
                                 "Query cursor position", NULL);
    env->funcall(env, fset, 2, args);
    
    // 注册字符大小查询
    args[0] = env->intern(env, "terminal-query-cell-size");
    args[1] = env->make_function(env, 0, 0, terminal_query_cell_size,
                                 "Query cell size", NULL);
    env->funcall(env, fset, 2, args);
    
    emacs_value provide = env->intern(env, "provide");
    emacs_value feature = env->intern(env, "terminal-query");
    env->funcall(env, provide, 1, &feature);
    
    return 0;
}
