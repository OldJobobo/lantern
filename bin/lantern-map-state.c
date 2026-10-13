#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define SCHEMA_VERSION 1U
#define MAX_STATE_BYTES (2U * 1024U * 1024U)
#define MAX_ENGINE 32U
#define SHA256_LENGTH 64U
#define MAX_LABEL 128U
#define MAX_COMMAND 96U
#define MAX_NODES 4096U
#define MAX_EDGES 16384U
#define MAX_COORDINATE 1000000LL
#define MAX_TURN 2147483647ULL
#define MAX_DEPTH 16U

struct parser {
  const unsigned char *data;
  size_t length;
  size_t position;
  unsigned int depth;
};

struct edge_ref {
  char from[16];
  char to[16];
  char direction[16];
};

struct validation {
  const char *engine;
  const char *sha256;
  char (*node_ids)[16];
  char (*position_ids)[16];
  struct edge_ref *edges;
  size_t node_count;
  size_t position_count;
  size_t edge_count;
  uint64_t maximum_last_seen;
  uint64_t turn;
  int has_turn;
};

static void skip_space(struct parser *parser) {
  while (parser->position < parser->length) {
    unsigned char value = parser->data[parser->position];
    if (value != ' ' && value != '\t' && value != '\r' && value != '\n') break;
    parser->position++;
  }
}

static int consume(struct parser *parser, unsigned char expected) {
  skip_space(parser);
  if (parser->position >= parser->length || parser->data[parser->position] != expected) return 0;
  parser->position++;
  return 1;
}

static int consume_separator(struct parser *parser, unsigned char closing) {
  if (!consume(parser, ',')) return 0;
  skip_space(parser);
  return parser->position < parser->length && parser->data[parser->position] != closing;
}

static int hex_value(unsigned char value) {
  if (value >= '0' && value <= '9') return (int)(value - '0');
  if (value >= 'a' && value <= 'f') return (int)(value - 'a') + 10;
  if (value >= 'A' && value <= 'F') return (int)(value - 'A') + 10;
  return -1;
}

static int append_byte(char *output, size_t capacity, size_t *length, unsigned int value) {
  if (value == 0U || value > 0xffU || *length + 1U >= capacity) return 0;
  output[(*length)++] = (char)value;
  return 1;
}

static int append_codepoint(char *output, size_t capacity, size_t *length, unsigned int codepoint) {
  if (codepoint == 0U || codepoint > 0x10ffffU ||
      (codepoint >= 0xd800U && codepoint <= 0xdfffU)) return 0;
  if (codepoint <= 0x7fU) return append_byte(output, capacity, length, codepoint);
  if (codepoint <= 0x7ffU)
    return append_byte(output, capacity, length, 0xc0U | (codepoint >> 6U)) &&
      append_byte(output, capacity, length, 0x80U | (codepoint & 0x3fU));
  if (codepoint <= 0xffffU)
    return append_byte(output, capacity, length, 0xe0U | (codepoint >> 12U)) &&
      append_byte(output, capacity, length, 0x80U | ((codepoint >> 6U) & 0x3fU)) &&
      append_byte(output, capacity, length, 0x80U | (codepoint & 0x3fU));
  return append_byte(output, capacity, length, 0xf0U | (codepoint >> 18U)) &&
    append_byte(output, capacity, length, 0x80U | ((codepoint >> 12U) & 0x3fU)) &&
    append_byte(output, capacity, length, 0x80U | ((codepoint >> 6U) & 0x3fU)) &&
    append_byte(output, capacity, length, 0x80U | (codepoint & 0x3fU));
}

static int parse_hex_quad(struct parser *parser, unsigned int *result) {
  unsigned int value = 0;
  for (int index = 0; index < 4; index++) {
    if (parser->position >= parser->length) return 0;
    int digit = hex_value(parser->data[parser->position++]);
    if (digit < 0) return 0;
    value = (value << 4U) | (unsigned int)digit;
  }
  *result = value;
  return 1;
}

static int append_raw_utf8(struct parser *parser, unsigned char lead, char *output,
                           size_t capacity, size_t *length) {
  unsigned int continuation_count;
  unsigned int codepoint;
  if (lead >= 0xc2U && lead <= 0xdfU) {
    continuation_count = 1U;
    codepoint = lead & 0x1fU;
  } else if (lead >= 0xe0U && lead <= 0xefU) {
    continuation_count = 2U;
    codepoint = lead & 0x0fU;
  } else if (lead >= 0xf0U && lead <= 0xf4U) {
    continuation_count = 3U;
    codepoint = lead & 0x07U;
  } else return 0;
  if (parser->length - parser->position < continuation_count) return 0;

  unsigned char bytes[4] = { lead, 0, 0, 0 };
  for (unsigned int index = 0; index < continuation_count; index++) {
    unsigned char continuation = parser->data[parser->position++];
    if ((continuation & 0xc0U) != 0x80U) return 0;
    bytes[index + 1U] = continuation;
    codepoint = (codepoint << 6U) | (continuation & 0x3fU);
  }
  if ((continuation_count == 1U && codepoint < 0x80U) ||
      (continuation_count == 2U && codepoint < 0x800U) ||
      (continuation_count == 3U && codepoint < 0x10000U) ||
      codepoint > 0x10ffffU || (codepoint >= 0xd800U && codepoint <= 0xdfffU)) return 0;
  for (unsigned int index = 0; index <= continuation_count; index++)
    if (!append_byte(output, capacity, length, bytes[index])) return 0;
  return 1;
}

static int parse_string(struct parser *parser, char *output, size_t capacity) {
  skip_space(parser);
  if (capacity == 0 || parser->position >= parser->length || parser->data[parser->position++] != '"') return 0;
  size_t output_length = 0;
  while (parser->position < parser->length) {
    unsigned char value = parser->data[parser->position++];
    if (value == '"') {
      output[output_length] = '\0';
      return 1;
    }
    if (value < 0x20U) return 0;
    if (value >= 0x80U) {
      if (!append_raw_utf8(parser, value, output, capacity, &output_length)) return 0;
      continue;
    }
    if (value != '\\') {
      if (!append_byte(output, capacity, &output_length, value)) return 0;
      continue;
    }

    if (parser->position >= parser->length) return 0;
    value = parser->data[parser->position++];
    if (value == '"' || value == '\\' || value == '/') {
      if (!append_byte(output, capacity, &output_length, value)) return 0;
    } else if (value == 'b' || value == 'f' || value == 'n' || value == 'r' || value == 't') {
      unsigned int decoded = value == 'b' ? '\b' : value == 'f' ? '\f' : value == 'n' ? '\n' : value == 'r' ? '\r' : '\t';
      if (!append_byte(output, capacity, &output_length, decoded)) return 0;
    } else if (value == 'u') {
      unsigned int first;
      if (!parse_hex_quad(parser, &first)) return 0;
      unsigned int codepoint = first;
      if (first >= 0xd800U && first <= 0xdbffU) {
        if (parser->length - parser->position < 6U || parser->data[parser->position] != '\\' ||
            parser->data[parser->position + 1U] != 'u') return 0;
        parser->position += 2U;
        unsigned int second;
        if (!parse_hex_quad(parser, &second) || second < 0xdc00U || second > 0xdfffU) return 0;
        codepoint = 0x10000U + ((first - 0xd800U) << 10U) + (second - 0xdc00U);
      } else if (first >= 0xdc00U && first <= 0xdfffU) return 0;
      if (!append_codepoint(output, capacity, &output_length, codepoint)) return 0;
    } else return 0;
  }
  return 0;
}

static int decimal_digit(unsigned char value) {
  return value >= '0' && value <= '9';
}

static int parse_json_number(struct parser *parser, double *result) {
  skip_space(parser);
  size_t start = parser->position;
  if (parser->position < parser->length && parser->data[parser->position] == '-') parser->position++;
  if (parser->position >= parser->length) return 0;
  if (parser->data[parser->position] == '0') {
    parser->position++;
    if (parser->position < parser->length && decimal_digit(parser->data[parser->position])) return 0;
  } else if (parser->data[parser->position] >= '1' && parser->data[parser->position] <= '9') {
    do { parser->position++; }
    while (parser->position < parser->length && decimal_digit(parser->data[parser->position]));
  } else return 0;

  if (parser->position < parser->length && parser->data[parser->position] == '.') {
    parser->position++;
    if (parser->position >= parser->length || !decimal_digit(parser->data[parser->position])) return 0;
    do { parser->position++; }
    while (parser->position < parser->length && decimal_digit(parser->data[parser->position]));
  }
  if (parser->position < parser->length &&
      (parser->data[parser->position] == 'e' || parser->data[parser->position] == 'E')) {
    parser->position++;
    if (parser->position < parser->length &&
        (parser->data[parser->position] == '+' || parser->data[parser->position] == '-')) parser->position++;
    if (parser->position >= parser->length || !decimal_digit(parser->data[parser->position])) return 0;
    do { parser->position++; }
    while (parser->position < parser->length && decimal_digit(parser->data[parser->position]));
  }

  const char *token = (const char *)parser->data + start;
  const char *token_end = (const char *)parser->data + parser->position;
  char *end = NULL;
  double value = strtod(token, &end); // The process remains in the C locale.
  if (!end || end != token_end || !isfinite(value)) return 0;
  *result = value;
  return 1;
}

static int parse_uint(struct parser *parser, uint64_t maximum, uint64_t *result) {
  double value;
  if (!parse_json_number(parser, &value) || value < 0.0 || value > (double)maximum) return 0;
  uint64_t integer = (uint64_t)value;
  if ((double)integer != value) return 0;
  *result = integer;
  return 1;
}

static int parse_int(struct parser *parser, int64_t minimum, int64_t maximum, int64_t *result) {
  double value;
  if (!parse_json_number(parser, &value) || value < (double)minimum || value > (double)maximum) return 0;
  int64_t integer = (int64_t)value;
  if ((double)integer != value) return 0;
  *result = integer;
  return 1;
}

static int parse_true(struct parser *parser) {
  skip_space(parser);
  if (parser->length - parser->position < 4U || memcmp(parser->data + parser->position, "true", 4U) != 0) return 0;
  parser->position += 4U;
  return 1;
}

static int valid_engine(const char *value) {
  size_t length = strlen(value);
  if (length == 0 || length > MAX_ENGINE) return 0;
  for (size_t index = 0; index < length; index++) {
    unsigned char character = (unsigned char)value[index];
    if (!(character >= 'a' && character <= 'z') && !(character >= '0' && character <= '9') && character != '_' && character != '-') return 0;
  }
  return 1;
}

static int valid_sha256(const char *value) {
  if (strlen(value) != SHA256_LENGTH) return 0;
  for (size_t index = 0; index < SHA256_LENGTH; index++)
    if (!((value[index] >= '0' && value[index] <= '9') || (value[index] >= 'a' && value[index] <= 'f'))) return 0;
  return 1;
}

static unsigned int decoded_codepoint(const unsigned char *value, size_t length, size_t *index) {
  unsigned char lead = value[(*index)++];
  if (lead < 0x80U) return lead;
  unsigned int continuation_count = lead < 0xe0U ? 1U : lead < 0xf0U ? 2U : 3U;
  unsigned int codepoint = lead & (continuation_count == 1U ? 0x1fU : continuation_count == 2U ? 0x0fU : 0x07U);
  for (unsigned int continuation = 0; continuation < continuation_count && *index < length; continuation++)
    codepoint = (codepoint << 6U) | (value[(*index)++] & 0x3fU);
  return codepoint;
}

static int ecmascript_trim_codepoint(unsigned int value) {
  return (value >= 0x0009U && value <= 0x000dU) || value == 0x0020U || value == 0x00a0U ||
    value == 0x1680U || (value >= 0x2000U && value <= 0x200aU) || value == 0x2028U ||
    value == 0x2029U || value == 0x202fU || value == 0x205fU || value == 0x3000U || value == 0xfeffU;
}

static int valid_label(const char *value) {
  const unsigned char *bytes = (const unsigned char *)value;
  size_t length = strlen(value);
  if (length == 0 || length > MAX_LABEL) return 0;
  size_t index = 0;
  unsigned int first = 0, last = 0;
  while (index < length) {
    unsigned int codepoint = decoded_codepoint(bytes, length, &index);
    if (first == 0U) first = codepoint;
    last = codepoint;
    if (codepoint <= 0x1fU || codepoint == 0x7fU) return 0;
  }
  return !ecmascript_trim_codepoint(first) && !ecmascript_trim_codepoint(last);
}

static int valid_room_id(const char *value) {
  if (strncmp(value, "room-", 5U) != 0 || value[5] < '1' || value[5] > '9') return 0;
  size_t length = strlen(value);
  if (length < 6U || length > 15U) return 0;
  for (size_t index = 6U; index < length; index++)
    if (value[index] < '0' || value[index] > '9') return 0;
  return 1;
}

static int valid_direction(const char *value) {
  static const char *directions[] = {
    "north", "northeast", "east", "southeast", "south", "southwest",
    "west", "northwest", "up", "down", "in", "out"
  };
  for (size_t index = 0; index < sizeof(directions) / sizeof(directions[0]); index++)
    if (strcmp(value, directions[index]) == 0) return 1;
  return 0;
}

static const char *movement_direction(const char *raw) {
  static const struct { const char *command; const char *direction; } commands[] = {
    {"n", "north"}, {"north", "north"}, {"go north", "north"},
    {"ne", "northeast"}, {"northeast", "northeast"}, {"go northeast", "northeast"},
    {"e", "east"}, {"east", "east"}, {"go east", "east"},
    {"se", "southeast"}, {"southeast", "southeast"}, {"go southeast", "southeast"},
    {"s", "south"}, {"south", "south"}, {"go south", "south"},
    {"sw", "southwest"}, {"southwest", "southwest"}, {"go southwest", "southwest"},
    {"w", "west"}, {"west", "west"}, {"go west", "west"},
    {"nw", "northwest"}, {"northwest", "northwest"}, {"go northwest", "northwest"},
    {"u", "up"}, {"up", "up"}, {"go up", "up"},
    {"d", "down"}, {"down", "down"}, {"go down", "down"},
    {"in", "in"}, {"go in", "in"}, {"out", "out"}, {"go out", "out"}
  };
  char normalized[MAX_COMMAND + 1U];
  size_t input_length = strlen(raw);
  size_t start = 0;
  while (start < input_length && (raw[start] == ' ' || raw[start] == '\t')) start++;
  size_t end = input_length;
  while (end > start && (raw[end - 1U] == ' ' || raw[end - 1U] == '\t')) end--;
  size_t output = 0;
  int pending_space = 0;
  for (size_t index = start; index < end; index++) {
    unsigned char value = (unsigned char)raw[index];
    if (value == ' ' || value == '\t') {
      pending_space = output > 0;
      continue;
    }
    if (pending_space) {
      if (output >= MAX_COMMAND) return NULL;
      normalized[output++] = ' ';
      pending_space = 0;
    }
    if (output >= MAX_COMMAND) return NULL;
    normalized[output++] = (char)tolower(value);
  }
  normalized[output] = '\0';
  for (size_t index = 0; index < sizeof(commands) / sizeof(commands[0]); index++)
    if (strcmp(normalized, commands[index].command) == 0) return commands[index].direction;
  return NULL;
}

static int enter_depth(struct parser *parser) {
  if (parser->depth >= MAX_DEPTH) return 0;
  parser->depth++;
  return 1;
}

static void leave_depth(struct parser *parser) {
  if (parser->depth > 0) parser->depth--;
}

static int parse_cartridge(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  unsigned int seen = 0;
  while (1) {
    skip_space(parser);
    if (consume(parser, '}')) break;
    char key[32];
    if (!parse_string(parser, key, sizeof(key)) || !consume(parser, ':')) return 0;
    if (strcmp(key, "engine") == 0 && !(seen & 1U)) {
      char engine[MAX_ENGINE + 1U];
      if (!parse_string(parser, engine, sizeof(engine)) || !valid_engine(engine) || strcmp(engine, validation->engine) != 0) return 0;
      seen |= 1U;
    } else if (strcmp(key, "sha256") == 0 && !(seen & 2U)) {
      char sha256[SHA256_LENGTH + 1U];
      if (!parse_string(parser, sha256, sizeof(sha256)) || !valid_sha256(sha256) || strcmp(sha256, validation->sha256) != 0) return 0;
      seen |= 2U;
    } else return 0;
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  return seen == 3U;
}

static int parse_node(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  unsigned int seen = 0;
  char id[16] = "";
  uint64_t first_seen = 0, last_seen = 0;
  while (1) {
    skip_space(parser);
    if (consume(parser, '}')) break;
    char key[32];
    if (!parse_string(parser, key, sizeof(key)) || !consume(parser, ':')) return 0;
    if (strcmp(key, "id") == 0 && !(seen & 1U)) {
      if (!parse_string(parser, id, sizeof(id)) || !valid_room_id(id)) return 0;
      seen |= 1U;
    } else if (strcmp(key, "label") == 0 && !(seen & 2U)) {
      char label[MAX_LABEL + 1U];
      if (!parse_string(parser, label, sizeof(label)) || !valid_label(label)) return 0;
      seen |= 2U;
    } else if (strcmp(key, "confidence") == 0 && !(seen & 4U)) {
      char confidence[16];
      if (!parse_string(parser, confidence, sizeof(confidence)) || strcmp(confidence, "confirmed") != 0) return 0;
      seen |= 4U;
    } else if (strcmp(key, "firstSeen") == 0 && !(seen & 8U)) {
      if (!parse_uint(parser, MAX_TURN, &first_seen)) return 0;
      seen |= 8U;
    } else if (strcmp(key, "lastSeen") == 0 && !(seen & 16U)) {
      if (!parse_uint(parser, MAX_TURN, &last_seen)) return 0;
      seen |= 16U;
    } else return 0;
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  if (seen != 31U || last_seen < first_seen || validation->node_count >= MAX_NODES) return 0;
  memcpy(validation->node_ids[validation->node_count++], id, sizeof(id));
  if (last_seen > validation->maximum_last_seen) validation->maximum_last_seen = last_seen;
  return 1;
}

static int parse_nodes(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '[')) return 0;
  skip_space(parser);
  if (consume(parser, ']')) { leave_depth(parser); return 1; }
  while (1) {
    if (!parse_node(parser, validation)) return 0;
    skip_space(parser);
    if (consume(parser, ']')) break;
    if (!consume_separator(parser, ']')) return 0;
  }
  leave_depth(parser);
  return 1;
}

static int parse_edge(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  unsigned int seen = 0;
  struct edge_ref edge;
  memset(&edge, 0, sizeof(edge));
  char command[MAX_COMMAND + 1U] = "";
  uint64_t traversals = 0;
  while (1) {
    skip_space(parser);
    if (consume(parser, '}')) break;
    char key[32];
    if (!parse_string(parser, key, sizeof(key)) || !consume(parser, ':')) return 0;
    if (strcmp(key, "from") == 0 && !(seen & 1U)) {
      if (!parse_string(parser, edge.from, sizeof(edge.from)) || !valid_room_id(edge.from)) return 0;
      seen |= 1U;
    } else if (strcmp(key, "to") == 0 && !(seen & 2U)) {
      if (!parse_string(parser, edge.to, sizeof(edge.to)) || !valid_room_id(edge.to)) return 0;
      seen |= 2U;
    } else if (strcmp(key, "direction") == 0 && !(seen & 4U)) {
      if (!parse_string(parser, edge.direction, sizeof(edge.direction)) || !valid_direction(edge.direction)) return 0;
      seen |= 4U;
    } else if (strcmp(key, "command") == 0 && !(seen & 8U)) {
      if (!parse_string(parser, command, sizeof(command))) return 0;
      seen |= 8U;
    } else if (strcmp(key, "confirmed") == 0 && !(seen & 16U)) {
      if (!parse_true(parser)) return 0;
      seen |= 16U;
    } else if (strcmp(key, "traversals") == 0 && !(seen & 32U)) {
      if (!parse_uint(parser, MAX_TURN, &traversals) || traversals == 0) return 0;
      seen |= 32U;
    } else return 0;
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  const char *command_result = movement_direction(command);
  if (seen != 63U || !command_result || strcmp(command_result, edge.direction) != 0 || validation->edge_count >= MAX_EDGES) return 0;
  validation->edges[validation->edge_count++] = edge;
  return 1;
}

static int parse_edges(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '[')) return 0;
  skip_space(parser);
  if (consume(parser, ']')) { leave_depth(parser); return 1; }
  while (1) {
    if (!parse_edge(parser, validation)) return 0;
    skip_space(parser);
    if (consume(parser, ']')) break;
    if (!consume_separator(parser, ']')) return 0;
  }
  leave_depth(parser);
  return 1;
}

static int parse_position(struct parser *parser) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  unsigned int seen = 0;
  while (1) {
    skip_space(parser);
    if (consume(parser, '}')) break;
    char key[8];
    int64_t coordinate = 0;
    if (!parse_string(parser, key, sizeof(key)) || !consume(parser, ':') ||
        !parse_int(parser, -MAX_COORDINATE, MAX_COORDINATE, &coordinate)) return 0;
    (void)coordinate;
    if (strcmp(key, "x") == 0 && !(seen & 1U)) seen |= 1U;
    else if (strcmp(key, "y") == 0 && !(seen & 2U)) seen |= 2U;
    else if (strcmp(key, "z") == 0 && !(seen & 4U)) seen |= 4U;
    else return 0;
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  return seen == 7U;
}

static int parse_positions(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  skip_space(parser);
  if (consume(parser, '}')) { leave_depth(parser); return 1; }
  while (1) {
    char id[16];
    if (validation->position_count >= MAX_NODES || !parse_string(parser, id, sizeof(id)) ||
        !valid_room_id(id) || !consume(parser, ':') || !parse_position(parser)) return 0;
    memcpy(validation->position_ids[validation->position_count++], id, sizeof(id));
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  return 1;
}

static int parse_layout(struct parser *parser, struct validation *validation) {
  if (!enter_depth(parser) || !consume(parser, '{')) return 0;
  unsigned int seen = 0;
  while (1) {
    skip_space(parser);
    if (consume(parser, '}')) break;
    char key[32];
    if (!parse_string(parser, key, sizeof(key)) || !consume(parser, ':')) return 0;
    if (strcmp(key, "seed") == 0 && !(seen & 1U)) {
      uint64_t seed = 0;
      if (!parse_uint(parser, UINT32_MAX, &seed) || seed == 0) return 0;
      seen |= 1U;
    } else if (strcmp(key, "positions") == 0 && !(seen & 2U)) {
      if (!parse_positions(parser, validation)) return 0;
      seen |= 2U;
    } else return 0;
    skip_space(parser);
    if (consume(parser, '}')) break;
    if (!consume_separator(parser, '}')) return 0;
  }
  leave_depth(parser);
  return seen == 3U;
}

static int compare_ids(const void *left, const void *right) {
  return strcmp((const char *)left, (const char *)right);
}

static int compare_edges(const void *left, const void *right) {
  const struct edge_ref *a = left;
  const struct edge_ref *b = right;
  int result = strcmp(a->from, b->from);
  if (result == 0) result = strcmp(a->to, b->to);
  if (result == 0) result = strcmp(a->direction, b->direction);
  return result;
}

static int has_id(char (*ids)[16], size_t count, const char *id) {
  return bsearch(id, ids, count, sizeof(ids[0]), compare_ids) != NULL;
}

static int validate_references(struct validation *validation) {
  qsort(validation->node_ids, validation->node_count, sizeof(validation->node_ids[0]), compare_ids);
  for (size_t index = 1; index < validation->node_count; index++)
    if (strcmp(validation->node_ids[index - 1U], validation->node_ids[index]) == 0) return 0;
  qsort(validation->position_ids, validation->position_count, sizeof(validation->position_ids[0]), compare_ids);
  for (size_t index = 0; index < validation->position_count; index++) {
    if (!has_id(validation->node_ids, validation->node_count, validation->position_ids[index])) return 0;
    if (index > 0 && strcmp(validation->position_ids[index - 1U], validation->position_ids[index]) == 0) return 0;
  }
  qsort(validation->edges, validation->edge_count, sizeof(validation->edges[0]), compare_edges);
  for (size_t index = 0; index < validation->edge_count; index++) {
    if (!has_id(validation->node_ids, validation->node_count, validation->edges[index].from) ||
        !has_id(validation->node_ids, validation->node_count, validation->edges[index].to)) return 0;
    if (index > 0 && compare_edges(&validation->edges[index - 1U], &validation->edges[index]) == 0) return 0;
  }
  return validation->has_turn && validation->maximum_last_seen <= validation->turn;
}

static int validate_json(const unsigned char *data, size_t length, const char *engine, const char *sha256) {
  struct validation validation;
  memset(&validation, 0, sizeof(validation));
  validation.engine = engine;
  validation.sha256 = sha256;
  validation.node_ids = calloc(MAX_NODES, sizeof(validation.node_ids[0]));
  validation.position_ids = calloc(MAX_NODES, sizeof(validation.position_ids[0]));
  validation.edges = calloc(MAX_EDGES, sizeof(validation.edges[0]));
  if (!validation.node_ids || !validation.position_ids || !validation.edges) {
    free(validation.node_ids); free(validation.position_ids); free(validation.edges);
    return 0;
  }

  struct parser parser = { data, length, 0, 0 };
  unsigned int seen = 0;
  int valid = enter_depth(&parser) && consume(&parser, '{');
  while (valid) {
    skip_space(&parser);
    if (consume(&parser, '}')) break;
    char key[32];
    if (!parse_string(&parser, key, sizeof(key)) || !consume(&parser, ':')) { valid = 0; break; }
    if (strcmp(key, "schemaVersion") == 0 && !(seen & 1U)) {
      uint64_t schema = 0;
      valid = parse_uint(&parser, UINT32_MAX, &schema) && schema == SCHEMA_VERSION;
      seen |= 1U;
    } else if (strcmp(key, "cartridge") == 0 && !(seen & 2U)) {
      valid = parse_cartridge(&parser, &validation); seen |= 2U;
    } else if (strcmp(key, "nodes") == 0 && !(seen & 4U)) {
      valid = parse_nodes(&parser, &validation); seen |= 4U;
    } else if (strcmp(key, "edges") == 0 && !(seen & 8U)) {
      valid = parse_edges(&parser, &validation); seen |= 8U;
    } else if (strcmp(key, "layout") == 0 && !(seen & 16U)) {
      valid = parse_layout(&parser, &validation); seen |= 16U;
    } else if (strcmp(key, "turn") == 0 && !(seen & 32U)) {
      valid = parse_uint(&parser, MAX_TURN, &validation.turn); validation.has_turn = valid; seen |= 32U;
    } else valid = 0;
    if (!valid) break;
    skip_space(&parser);
    if (consume(&parser, '}')) break;
    if (!consume_separator(&parser, '}')) { valid = 0; break; }
  }
  leave_depth(&parser);
  skip_space(&parser);
  valid = valid && seen == 63U && parser.position == parser.length && validate_references(&validation);
  free(validation.node_ids); free(validation.position_ids); free(validation.edges);
  return valid;
}

static int write_all(int descriptor, const unsigned char *data, size_t length) {
  size_t written = 0;
  while (written < length) {
    ssize_t result = write(descriptor, data + written, length - written);
    if (result < 0 && errno == EINTR) continue;
    if (result <= 0) return 0;
    written += (size_t)result;
  }
  return 1;
}

static int read_bounded(int descriptor, unsigned char **output, size_t *length) {
  unsigned char *buffer = malloc(MAX_STATE_BYTES + 1U);
  if (!buffer) return 0;
  size_t used = 0;
  while (used <= MAX_STATE_BYTES) {
    ssize_t result = read(descriptor, buffer + used, MAX_STATE_BYTES + 1U - used);
    if (result < 0 && errno == EINTR) continue;
    if (result < 0) { free(buffer); return 0; }
    if (result == 0) break;
    used += (size_t)result;
  }
  if (used > MAX_STATE_BYTES) { free(buffer); return 0; }
  buffer[used] = '\0';
  *output = buffer;
  *length = used;
  return 1;
}

#define DIRECTORY_UNSAFE (-1)
#define DIRECTORY_ABSENT (-2)

static int owned_directory(int descriptor, int require_private_mode) {
  struct stat metadata;
  return fstat(descriptor, &metadata) == 0 && S_ISDIR(metadata.st_mode) &&
    metadata.st_uid == getuid() && (metadata.st_mode & 0022) == 0 &&
    (!require_private_mode || (metadata.st_mode & 0777) == 0700);
}

static int open_owned_child_directory(int parent, const char *name, int create,
                                      int require_private_mode) {
  int descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0) {
    if (errno != ENOENT) return DIRECTORY_UNSAFE;
    if (!create) return DIRECTORY_ABSENT;
    if (mkdirat(parent, name, 0700) != 0) return DIRECTORY_UNSAFE;
    if (fsync(parent) != 0) return DIRECTORY_UNSAFE;
    descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0 || fchmod(descriptor, 0700) != 0 || fsync(descriptor) != 0) {
      if (descriptor >= 0) close(descriptor);
      return DIRECTORY_UNSAFE;
    }
  }
  if (!owned_directory(descriptor, require_private_mode)) {
    close(descriptor);
    return DIRECTORY_UNSAFE;
  }
  return descriptor;
}

static int open_absolute_directory(const char *path, int create) {
  if (!path || path[0] != '/') return DIRECTORY_UNSAFE;
  int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (current < 0) return DIRECTORY_UNSAFE;
  const char *cursor = path + 1;
  while (*cursor) {
    while (*cursor == '/') cursor++;
    if (!*cursor) break;
    const char *end = cursor;
    while (*end && *end != '/') end++;
    size_t length = (size_t)(end - cursor);
    if (length == 0 || length > NAME_MAX ||
        (length == 1U && cursor[0] == '.') ||
        (length == 2U && cursor[0] == '.' && cursor[1] == '.')) {
      close(current);
      return DIRECTORY_UNSAFE;
    }
    char component[NAME_MAX + 1U];
    memcpy(component, cursor, length);
    component[length] = '\0';
    int next = openat(current, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0) {
      if (errno != ENOENT) { close(current); return DIRECTORY_UNSAFE; }
      if (!create) { close(current); return DIRECTORY_ABSENT; }
      if (mkdirat(current, component, 0700) != 0 || fsync(current) != 0) {
        close(current);
        return DIRECTORY_UNSAFE;
      }
      next = openat(current, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
      if (next < 0 || fchmod(next, 0700) != 0 || fsync(next) != 0) {
        if (next >= 0) close(next);
        close(current);
        return DIRECTORY_UNSAFE;
      }
    }
    close(current);
    current = next;
    cursor = end;
  }
  if (!owned_directory(current, 0)) {
    close(current);
    return DIRECTORY_UNSAFE;
  }
  return current;
}

static int open_state_root(int create) {
  const char *xdg = getenv("XDG_STATE_HOME");
  if (xdg && xdg[0]) return open_absolute_directory(xdg, create);

  const char *home_path = getenv("HOME");
  int home = open_absolute_directory(home_path, 0);
  if (home < 0) return home;
  int local = open_owned_child_directory(home, ".local", create, 0);
  close(home);
  if (local < 0) return local;
  int state = open_owned_child_directory(local, "state", create, 0);
  close(local);
  return state;
}

static int open_maps_directory(int create) {
  int root = open_state_root(create);
  if (root < 0) return root;
  // v0.1.x creates this shared save/window-state parent with mode 0755.
  // Preserve that directory; only maps and its files must be private.
  int lantern = open_owned_child_directory(root, "lantern", create, 0);
  close(root);
  if (lantern < 0) return lantern;
  int maps = open_owned_child_directory(lantern, "maps", create, 1);
  close(lantern);
  return maps;
}

static int target_metadata(int maps, const char *filename, struct stat *metadata) {
  if (fstatat(maps, filename, metadata, AT_SYMLINK_NOFOLLOW) != 0) return errno == ENOENT ? 0 : -1;
  if (!S_ISREG(metadata->st_mode) || metadata->st_uid != getuid()) return -1;
  return 1;
}

static int operation_read(int maps, const char *filename, const char *engine, const char *sha256) {
  struct stat before;
  if (target_metadata(maps, filename, &before) != 1 || (before.st_mode & 0777) != 0600 ||
      before.st_size < 0 || (uintmax_t)before.st_size > MAX_STATE_BYTES) return 65;
  int descriptor = openat(maps, filename, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (descriptor < 0) return 65;
  struct stat after;
  if (fstat(descriptor, &after) != 0 || !S_ISREG(after.st_mode) || after.st_uid != getuid() ||
      (after.st_mode & 0777) != 0600 || after.st_dev != before.st_dev || after.st_ino != before.st_ino) {
    close(descriptor); return 65;
  }
  unsigned char *data = NULL;
  size_t length = 0;
  int ok = read_bounded(descriptor, &data, &length);
  close(descriptor);
  if (!ok || !validate_json(data, length, engine, sha256)) { free(data); return 65; }
  ok = write_all(STDOUT_FILENO, data, length);
  free(data);
  return ok ? 0 : 74;
}

static int operation_write(int maps, const char *filename, const char *engine, const char *sha256) {
  unsigned char *data = NULL;
  size_t length = 0;
  if (!read_bounded(STDIN_FILENO, &data, &length) || !validate_json(data, length, engine, sha256)) {
    free(data); return 65;
  }
  struct stat existing;
  int metadata = target_metadata(maps, filename, &existing);
  if (metadata < 0 || (metadata == 1 && (existing.st_mode & 0777) != 0600)) { free(data); return 65; }

  char temporary[160];
  if (snprintf(temporary, sizeof(temporary), ".%s.tmp.%lu", filename, (unsigned long)getpid()) >= (int)sizeof(temporary)) {
    free(data); return 74;
  }
  int descriptor = openat(maps, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0) { free(data); return 74; }
  int ok = fchmod(descriptor, 0600) == 0 && write_all(descriptor, data, length) && fsync(descriptor) == 0;
  free(data);
  if (close(descriptor) != 0) ok = 0;
  if (!ok || renameat(maps, temporary, maps, filename) != 0) {
    unlinkat(maps, temporary, 0);
    return 74;
  }
  if (fsync(maps) != 0) return 74;
  return 0;
}

static int operation_reset(int maps, const char *filename) {
  struct stat metadata;
  int result = target_metadata(maps, filename, &metadata);
  if (result == 0) return 0;
  if (result < 0 || (metadata.st_mode & 0777) != 0600) return 65;
  if (unlinkat(maps, filename, 0) != 0 || fsync(maps) != 0) return 74;
  return 0;
}

int main(int argc, char **argv) {
  if (argc != 4 || !valid_engine(argv[2]) || !valid_sha256(argv[3])) return 64;
  int create = strcmp(argv[1], "write") == 0;
  if (!create && strcmp(argv[1], "read") != 0 && strcmp(argv[1], "reset") != 0) return 64;

  char filename[MAX_ENGINE + 1U + SHA256_LENGTH + 5U + 1U];
  if (snprintf(filename, sizeof(filename), "%s-%s.json", argv[2], argv[3]) >= (int)sizeof(filename)) return 64;
  int maps = open_maps_directory(create);
  if (maps < 0) return strcmp(argv[1], "reset") == 0 && maps == DIRECTORY_ABSENT ? 0 : 65;

  int result;
  if (strcmp(argv[1], "read") == 0) result = operation_read(maps, filename, argv[2], argv[3]);
  else if (strcmp(argv[1], "write") == 0) result = operation_write(maps, filename, argv[2], argv[3]);
  else result = operation_reset(maps, filename);
  close(maps);
  return result;
}
