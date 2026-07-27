package cgra_pkg;

typedef enum logic [2:0] {
    NORTH, //N
    SOUTH, //S
    EAST,  //E
    WEST,  //W
    ROW,   //R
    COL,   //C
    CONST, //X
    SELF   //F
} source_t;

typedef enum logic [1:0] {
    ADD,
    SUB,
    MUL,
    ABS
} opcode_t;

typedef enum logic [1:0] {
    GT,
    LT,
    EQ,
    FALSE
} compare_t;

endpackage
