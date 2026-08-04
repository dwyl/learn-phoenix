#include <algorithm>
#include <erl_nif.h>
#include <fine.hpp>
#include <functional>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <tuple>
#include <variant>

#include <lexbor/html/html.h>
#include <lexbor/css/css.h>
#include <lexbor/selectors/selectors.h>
#include <lexbor/dom/dom.h>

namespace lazy_html {

// Ensures the given cleanup function is executed when the guard goes
// out of scope.
class ScopeGuard {
public:
  ScopeGuard(std::function<void()> fun) : fun(fun), active(true) {}

  ~ScopeGuard() {
    if (active) {
      fun();
    }
  }

  void deactivate() { active = false; }

private:
  std::function<void()> fun;
  bool active;
};

namespace atoms {
auto ElixirLazyHTML = fine::Atom("Elixir.LazyHTML");
auto comment = fine::Atom("comment");
auto resource = fine::Atom("resource");
} // namespace atoms

struct DocumentRef {
  lxb_html_document_t *document;

  DocumentRef(lxb_html_document_t *document) : document(document) {}

  ~DocumentRef() { lxb_html_document_destroy(this->document); }
};

struct LazyHTML {
  std::shared_ptr<DocumentRef> document_ref;
  std::vector<lxb_dom_node_t *> nodes;
  bool from_selector;

  LazyHTML(std::shared_ptr<DocumentRef> document_ref,
           std::vector<lxb_dom_node_t *> nodes, bool from_selector)
      : document_ref(document_ref), nodes(nodes), from_selector(from_selector) {
  }
};

FINE_RESOURCE(LazyHTML);

struct ExLazyHTML {
  fine::ResourcePtr<LazyHTML> resource;

  ExLazyHTML() {}
  ExLazyHTML(fine::ResourcePtr<LazyHTML> resource) : resource(resource) {}

  static constexpr auto module = &atoms::ElixirLazyHTML;

  static constexpr auto fields() {
    return std::make_tuple(
        std::make_tuple(&ExLazyHTML::resource, &atoms::resource));
  }
};

ERL_NIF_TERM make_new_binary(ErlNifEnv *env, size_t size,
                             const unsigned char *data) {
  ERL_NIF_TERM term;
  auto term_data = enif_make_new_binary(env, size, &term);
  memcpy(term_data, data, size);
  return term;
}

ExLazyHTML from_document(ErlNifEnv *env, ErlNifBinary html) {
  auto document = lxb_html_document_create();
  if (document == NULL) {
    throw std::runtime_error("failed to create document");
  }
  auto document_guard =
      ScopeGuard([&]() { lxb_html_document_destroy(document); });

  auto status = lxb_html_document_parse(document, html.data, html.size);
  if (status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to parse html document");
  }

  auto document_ref = std::make_shared<DocumentRef>(document);
  document_guard.deactivate();

  auto nodes = std::vector<lxb_dom_node_t *>();
  for (auto node = lxb_dom_node_first_child(lxb_dom_interface_node(document));
       node != NULL; node = lxb_dom_node_next(node)) {
    nodes.push_back(node);
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(document_ref, nodes, false));
}

FINE_NIF(from_document, ERL_NIF_DIRTY_JOB_CPU_BOUND);

ExLazyHTML from_fragment(ErlNifEnv *env, ErlNifBinary html) {
  auto document = lxb_html_document_create();
  if (document == NULL) {
    throw std::runtime_error("failed to create document");
  }
  auto document_guard =
      ScopeGuard([&]() { lxb_html_document_destroy(document); });

  auto context = lxb_dom_document_create_element(
      &document->dom_document, reinterpret_cast<const lxb_char_t *>("body"), 4,
      NULL);

  auto parse_root =
      lxb_html_document_parse_fragment(document, context, html.data, html.size);
  if (parse_root == NULL) {
    throw std::runtime_error("failed to parse html fragment");
  }

  auto document_ref = std::make_shared<DocumentRef>(document);
  document_guard.deactivate();

  auto nodes = std::vector<lxb_dom_node_t *>();
  for (auto node = lxb_dom_node_first_child(parse_root); node != NULL;
       node = lxb_dom_node_next(node)) {
    nodes.push_back(node);
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(document_ref, nodes, false));
}

FINE_NIF(from_fragment, ERL_NIF_DIRTY_JOB_CPU_BOUND);

void append_escaping(std::string &html, const unsigned char *data,
                     size_t length, size_t unescaped_prefix_size = 0) {
  size_t offset = 0;
  size_t size = unescaped_prefix_size;

  for (size_t i = unescaped_prefix_size; i < length; ++i) {
    auto ch = data[i];
    if (ch == '<') {
      if (size > 0) {
        html.append(reinterpret_cast<const char *>(data + offset), size);
      }
      offset = i + 1;
      size = 0;
      html.append("&lt;");
    } else if (ch == '>') {
      if (size > 0) {
        html.append(reinterpret_cast<const char *>(data + offset), size);
      }
      offset = i + 1;
      size = 0;
      html.append("&gt;");
    } else if (ch == '&') {
      if (size > 0) {
        html.append(reinterpret_cast<const char *>(data + offset), size);
      }
      offset = i + 1;
      size = 0;
      html.append("&amp;");
    } else if (ch == '"') {
      if (size > 0) {
        html.append(reinterpret_cast<const char *>(data + offset), size);
      }
      offset = i + 1;
      size = 0;
      html.append("&quot;");
    } else if (ch == '\'') {
      if (size > 0) {
        html.append(reinterpret_cast<const char *>(data + offset), size);
      }
      offset = i + 1;
      size = 0;
      html.append("&#39;");
    } else {
      size++;
    }
  }

  if (size > 0) {
    html.append(reinterpret_cast<const char *>(data + offset), size);
  }
}

bool is_noescape_text_node(lxb_dom_node_t *node) {
  if (node->parent != NULL) {
    switch (node->parent->local_name) {
    case LXB_TAG_STYLE:
    case LXB_TAG_SCRIPT:
    case LXB_TAG_XMP:
    case LXB_TAG_IFRAME:
    case LXB_TAG_NOEMBED:
    case LXB_TAG_NOFRAMES:
    case LXB_TAG_PLAINTEXT:
      return true;
    }
  }

  return false;
}

size_t leading_whitespace_size(const unsigned char *data, size_t length) {
  auto size = 0;

  for (size_t i = 0; i < length; i++) {
    auto ch = data[i];

    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      size++;
    } else {
      return size;
    }
  }

  return size;
}

lxb_dom_node_t *template_aware_first_child(lxb_dom_node_t *node) {
  if (lxb_html_tree_node_is(node, LXB_TAG_TEMPLATE)) {
    // <template> elements don't have direct children, instead they hold
    // a document fragment node, so we reach for its first child instead.
    return lxb_html_interface_template(node)->content->node.first_child;
  } else {
    return lxb_dom_node_first_child(node);
  }
}

void append_node_html(lxb_dom_node_t *node, bool skip_whitespace_nodes,
                      std::string &html) {
  if (node->type == LXB_DOM_NODE_TYPE_TEXT) {
    auto character_data = lxb_dom_interface_character_data(node);

    auto whitespace_size = leading_whitespace_size(character_data->data.data,
                                                   character_data->data.length);

    if (whitespace_size == character_data->data.length &&
        skip_whitespace_nodes) {
      // Append nothing
    } else {
      if (is_noescape_text_node(node)) {
        html.append(reinterpret_cast<char *>(character_data->data.data),
                    character_data->data.length);
      } else {
        append_escaping(html, character_data->data.data,
                        character_data->data.length, whitespace_size);
      }
    }
  } else if (node->type == LXB_DOM_NODE_TYPE_COMMENT) {
    auto character_data = lxb_dom_interface_character_data(node);
    html.append("<!--");
    html.append(reinterpret_cast<char *>(character_data->data.data),
                character_data->data.length);
    html.append("-->");
  } else if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
    auto element = lxb_dom_interface_element(node);
    size_t name_length;
    auto name = lxb_dom_element_qualified_name(element, &name_length);
    if (name == NULL) {
      throw std::runtime_error("failed to read tag name");
    }
    html.append("<");
    html.append(reinterpret_cast<const char *>(name), name_length);

    for (auto attribute = lxb_dom_element_first_attribute(element);
         attribute != NULL;
         attribute = lxb_dom_element_next_attribute(attribute)) {
      html.append(" ");

      size_t name_length;
      auto name = lxb_dom_attr_qualified_name(attribute, &name_length);
      html.append(reinterpret_cast<const char *>(name), name_length);

      html.append("=\"");

      size_t value_length;
      auto value = lxb_dom_attr_value(attribute, &value_length);
      append_escaping(html, value, value_length);

      html.append("\"");
    }

    if (lxb_html_node_is_void(node)) {
      html.append("/>");
    } else {
      html.append(">");
      for (auto child = template_aware_first_child(node); child != NULL;
           child = lxb_dom_node_next(child)) {
        append_node_html(child, skip_whitespace_nodes, html);
      }
      html.append("</");
      html.append(reinterpret_cast<const char *>(name), name_length);
      html.append(">");
    }
  }
}

std::string to_html(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                    bool skip_whitespace_nodes) {
  auto string = std::string();

  for (auto node : ex_lazy_html.resource->nodes) {
    append_node_html(node, skip_whitespace_nodes, string);
  }

  return string;
}

FINE_NIF(to_html, 0);

ERL_NIF_TERM attributes_to_term(ErlNifEnv *env, lxb_dom_element_t *element,
                                bool sort_attributes) {
  auto attributes = std::vector<std::tuple<std::string, std::string>>();

  for (auto attribute = lxb_dom_element_first_attribute(element);
       attribute != NULL;
       attribute = lxb_dom_element_next_attribute(attribute)) {
    size_t name_length;
    auto name = lxb_dom_attr_qualified_name(attribute, &name_length);

    size_t value_length;
    auto value = lxb_dom_attr_value(attribute, &value_length);

    auto name_string =
        std::string(reinterpret_cast<const char *>(name), name_length);
    auto value_string =
        std::string(reinterpret_cast<const char *>(value), value_length);

    attributes.push_back(std::make_tuple(name_string, value_string));
  }

  if (sort_attributes) {
    std::sort(attributes.begin(), attributes.end(),
              [](const auto &left, const auto &right) {
                return std::get<0>(left) < std::get<0>(right);
              });
  }

  return fine::encode(env, attributes);
}

void node_to_tree(ErlNifEnv *env, fine::ResourcePtr<LazyHTML> &resource,
                  lxb_dom_node_t *node, std::vector<ERL_NIF_TERM> &tree,
                  bool sort_attributes, bool skip_whitespace_nodes) {
  if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
    auto element = lxb_dom_interface_element(node);

    size_t name_length;
    auto name = lxb_dom_element_qualified_name(element, &name_length);
    if (name == NULL) {
      throw std::runtime_error("failed to read tag name");
    }
    auto name_term = make_new_binary(env, name_length, name);

    auto attrs_term = attributes_to_term(env, element, sort_attributes);

    auto children = std::vector<ERL_NIF_TERM>();
    for (auto child = template_aware_first_child(node); child != NULL;
         child = lxb_dom_node_next(child)) {
      node_to_tree(env, resource, child, children, sort_attributes,
                   skip_whitespace_nodes);
    }

    auto children_term = enif_make_list_from_array(
        env, children.data(), static_cast<unsigned int>(children.size()));

    tree.push_back(enif_make_tuple3(env, name_term, attrs_term, children_term));
  } else if (node->type == LXB_DOM_NODE_TYPE_TEXT) {
    auto character_data = lxb_dom_interface_character_data(node);

    auto whitespace_size = leading_whitespace_size(character_data->data.data,
                                                   character_data->data.length);

    if (whitespace_size == character_data->data.length &&
        skip_whitespace_nodes) {
      // Append nothing
    } else {
      auto term = fine::make_resource_binary(
          env, resource, reinterpret_cast<char *>(character_data->data.data),
          character_data->data.length);
      tree.push_back(term);
    }
  } else if (node->type == LXB_DOM_NODE_TYPE_COMMENT) {
    auto character_data = lxb_dom_interface_character_data(node);
    auto term = fine::make_resource_binary(
        env, resource, reinterpret_cast<char *>(character_data->data.data),
        character_data->data.length);
    tree.push_back(
        enif_make_tuple2(env, fine::encode(env, atoms::comment), term));
  }
}

fine::Term to_tree(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                   bool sort_attributes, bool skip_whitespace_nodes) {
  auto tree = std::vector<ERL_NIF_TERM>();

  for (auto node : ex_lazy_html.resource->nodes) {
    node_to_tree(env, ex_lazy_html.resource, node, tree, sort_attributes,
                 skip_whitespace_nodes);
  }

  return enif_make_list_from_array(env, tree.data(),
                                   static_cast<unsigned int>(tree.size()));
}

FINE_NIF(to_tree, 0);

std::optional<uintptr_t> get_tag_namespace(ErlNifBinary name) {
  if (strncmp("svg", reinterpret_cast<char *>(name.data), name.size) == 0) {
    // For SVG we explicitly set the namespace, similar to
    // `document.createElementNS`. It is important because attribute
    // names are lowercased for HTML elements, but should not be
    // lowercased inside SVG.
    return LXB_NS_SVG;
  }

  return std::nullopt;
}

lxb_dom_node_t *node_from_tree_item(ErlNifEnv *env,
                                    lxb_html_document_t *document,
                                    fine::Term item,
                                    std::optional<uintptr_t> ns) {
  using ExText = ErlNifBinary;
  using ExElement =
      std::tuple<ErlNifBinary,
                 std::vector<std::tuple<ErlNifBinary, ErlNifBinary>>,
                 std::vector<fine::Term>>;
  using ExComment = std::tuple<fine::Atom, ErlNifBinary>;

  auto decoded =
      fine::decode<std::variant<ExText, ExElement, ExComment>>(env, item);

  if (auto text_ptr = std::get_if<ExText>(&decoded)) {
    auto text = lxb_dom_document_create_text_node(
        &document->dom_document, text_ptr->data, text_ptr->size);
    if (text == NULL) {
      throw std::runtime_error("failed to create text node");
    }
    return lxb_dom_interface_node(text);
  } else if (auto element_ptr = std::get_if<ExElement>(&decoded)) {
    const auto &[name, attributes, children_tree] = *element_ptr;

    auto element = lxb_dom_document_create_element(&document->dom_document,
                                                   name.data, name.size, NULL);

    auto node = lxb_dom_interface_node(element);

    if (!ns) {
      ns = get_tag_namespace(name);
    }

    if (ns) {
      node->ns = ns.value();
    }

    for (auto &[key, value] : attributes) {
      auto attr = lxb_dom_element_set_attribute(element, key.data, key.size,
                                                value.data, value.size);
      if (attr == NULL) {
        throw std::runtime_error("failed to set element attribute");
      }
    }

    if (lxb_html_tree_node_is(node, LXB_TAG_TEMPLATE)) {
      // <template> elements don't have direct children, instead they hold
      // a document fragment node, so we insert into the fragment instead.
      node = &lxb_html_interface_template(node)->content->node;
    }

    for (auto child_item : children_tree) {
      auto child_node = node_from_tree_item(env, document, child_item, ns);
      lxb_dom_node_insert_child(node, child_node);
    }

    return lxb_dom_interface_node(element);
  } else if (auto comment_ptr = std::get_if<ExComment>(&decoded)) {
    const auto &[atom, content] = *comment_ptr;

    if (!(atom == atoms::comment)) {
      throw std::invalid_argument("tuple contains unexpected atom: :" +
                                  atom.to_string());
    }

    auto comment = lxb_dom_document_create_comment(&document->dom_document,
                                                   content.data, content.size);
    if (comment == NULL) {
      throw std::runtime_error("failed to create comment node");
    }
    return lxb_dom_interface_node(comment);
  }

  throw std::logic_error("unreachable");
}

ExLazyHTML from_tree(ErlNifEnv *env, std::vector<fine::Term> tree) {
  auto document = lxb_html_document_create();
  if (document == NULL) {
    throw std::runtime_error("failed to create document");
  }
  auto document_guard =
      ScopeGuard([&]() { lxb_html_document_destroy(document); });

  auto root = lxb_dom_interface_node(document);
  auto nodes = std::vector<lxb_dom_node_t *>();

  for (auto tree_node : tree) {
    auto node = node_from_tree_item(env, document, tree_node, std::nullopt);
    lxb_dom_node_insert_child(root, lxb_dom_interface_node(node));
    nodes.push_back(node);
  }

  auto document_ref = std::make_shared<DocumentRef>(document);
  document_guard.deactivate();

  return ExLazyHTML(fine::make_resource<LazyHTML>(document_ref, nodes, false));
}

FINE_NIF(from_tree, 0);

lxb_css_selector_list_t *parse_css_selector(lxb_css_parser_t *parser,
                                            ErlNifBinary css_selector) {
  auto css_selector_list =
      lxb_css_selectors_parse(parser, css_selector.data, css_selector.size);
  if (parser->status == LXB_STATUS_ERROR_UNEXPECTED_DATA) {
    throw std::invalid_argument(
        "got invalid css selector: " +
        std::string(reinterpret_cast<char *>(css_selector.data),
                    css_selector.size));
  }
  if (parser->status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to parse css selector");
  }

  return css_selector_list;
}

ExLazyHTML query(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                 ErlNifBinary css_selector) {
  auto parser = lxb_css_parser_create();
  auto status = lxb_css_parser_init(parser, NULL);
  if (status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to create css parser");
  }
  auto parser_guard =
      ScopeGuard([&]() { lxb_css_parser_destroy(parser, true); });

  auto css_selector_list = parse_css_selector(parser, css_selector);
  auto css_selector_list_guard = ScopeGuard(
      [&]() { lxb_css_selector_list_destroy_memory(css_selector_list); });

  auto selectors = lxb_selectors_create();
  status = lxb_selectors_init(selectors);
  if (status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to create selectors");
  }
  auto selectors_guard =
      ScopeGuard([&]() { lxb_selectors_destroy(selectors, true); });

  // By default the find callback can be called multiple times with
  // the same element, if it matches multiple selectors in the list.
  // This options changes the behaviour, so that we get unique elements.
  lxb_selectors_opt_set(selectors, static_cast<lxb_selectors_opt_t>(
                                       LXB_SELECTORS_OPT_MATCH_FIRST |
                                       LXB_SELECTORS_OPT_MATCH_ROOT));

  auto nodes = std::vector<lxb_dom_node_t *>();

  for (auto node : ex_lazy_html.resource->nodes) {
    status = lxb_selectors_find(
        selectors, node, css_selector_list,
        [](lxb_dom_node_t *node, lxb_css_selector_specificity_t spec,
           void *ctx) -> lxb_status_t {
          auto nodes_ptr = static_cast<std::vector<lxb_dom_node_t *> *>(ctx);
          nodes_ptr->push_back(node);
          return LXB_STATUS_OK;
        },
        &nodes);
    if (status != LXB_STATUS_OK) {
      throw std::runtime_error("failed to run find");
    }
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(
      ex_lazy_html.resource->document_ref, nodes, true));
}

FINE_NIF(query, ERL_NIF_DIRTY_JOB_CPU_BOUND);

ExLazyHTML filter(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                  ErlNifBinary css_selector) {
  auto parser = lxb_css_parser_create();
  auto status = lxb_css_parser_init(parser, NULL);
  if (status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to create css parser");
  }
  auto parser_guard =
      ScopeGuard([&]() { lxb_css_parser_destroy(parser, true); });

  auto css_selector_list = parse_css_selector(parser, css_selector);
  auto css_selector_list_guard = ScopeGuard(
      [&]() { lxb_css_selector_list_destroy_memory(css_selector_list); });

  auto selectors = lxb_selectors_create();
  status = lxb_selectors_init(selectors);
  if (status != LXB_STATUS_OK) {
    throw std::runtime_error("failed to create selectors");
  }
  auto selectors_guard =
      ScopeGuard([&]() { lxb_selectors_destroy(selectors, true); });

  // By default the find callback can be called multiple times with
  // the same element, if it matches multiple selectors in the list.
  // This options changes the behaviour, so that we get unique elements.
  lxb_selectors_opt_set(selectors, LXB_SELECTORS_OPT_MATCH_FIRST);

  auto nodes = std::vector<lxb_dom_node_t *>();

  for (auto node : ex_lazy_html.resource->nodes) {
    status = lxb_selectors_match_node(
        selectors, node, css_selector_list,
        [](lxb_dom_node_t *node, lxb_css_selector_specificity_t spec,
           void *ctx) -> lxb_status_t {
          auto nodes_ptr = static_cast<std::vector<lxb_dom_node_t *> *>(ctx);
          nodes_ptr->push_back(node);
          return LXB_STATUS_OK;
        },
        &nodes);
    if (status != LXB_STATUS_OK) {
      throw std::runtime_error("failed to run match");
    }
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(
      ex_lazy_html.resource->document_ref, nodes, true));
}

FINE_NIF(filter, 0);

bool matches_id(lxb_dom_node_t *node, ErlNifBinary *id) {
  if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
    auto element = lxb_dom_interface_element(node);

    size_t value_length;
    auto value = lxb_dom_element_get_attribute(
        element, reinterpret_cast<const lxb_char_t *>("id"), 2, &value_length);

    if (value != NULL && value_length == id->size &&
        lexbor_str_data_ncmp(value, id->data, id->size)) {
      return true;
    }
  }

  return false;
}

ExLazyHTML query_by_id(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                       ErlNifBinary id) {
  auto nodes = std::vector<lxb_dom_node_t *>();

  auto ctx = std::make_tuple(&nodes, &id);

  for (auto node : ex_lazy_html.resource->nodes) {
    if (matches_id(node, &id)) {
      nodes.push_back(node);
    }

    lxb_dom_node_simple_walk(
        node,
        [](lxb_dom_node_t *node, void *ctx) -> lexbor_action_t {
          auto [nodes_ptr, id_ptr] = *static_cast<
              std::tuple<std::vector<lxb_dom_node_t *> *, ErlNifBinary *> *>(
              ctx);
          if (matches_id(node, id_ptr)) {
            nodes_ptr->push_back(node);
          }

          return LEXBOR_ACTION_OK;
        },
        &ctx);
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(
      ex_lazy_html.resource->document_ref, nodes, true));
}

FINE_NIF(query_by_id, 0);

ExLazyHTML child_nodes(ErlNifEnv *env, ExLazyHTML ex_lazy_html) {
  auto nodes = std::vector<lxb_dom_node_t *>();

  for (auto node : ex_lazy_html.resource->nodes) {
    for (auto child = lxb_dom_node_first_child(node); child != NULL;
         child = lxb_dom_node_next(child)) {
      nodes.push_back(child);
    }
  }

  return ExLazyHTML(fine::make_resource<LazyHTML>(
      ex_lazy_html.resource->document_ref, nodes, true));
}

FINE_NIF(child_nodes, 0);

std::string text(ErlNifEnv *env, ExLazyHTML ex_lazy_html) {
  auto document = ex_lazy_html.resource->document_ref->document;

  auto content = std::string();

  for (auto node : ex_lazy_html.resource->nodes) {
    if (node->type == LXB_DOM_NODE_TYPE_ELEMENT ||
        node->type == LXB_DOM_NODE_TYPE_TEXT) {
      size_t size;
      auto text = lxb_dom_node_text_content(node, &size);
      if (text == NULL) {
        throw std::runtime_error("failed to get element text content");
      }
      auto text_guard = ScopeGuard([&]() {
        lxb_dom_document_destroy_text(lxb_dom_interface_document(document),
                                      text);
      });

      content.append(reinterpret_cast<char *>(text), size);
    }
  }

  return content;
}

FINE_NIF(text, 0);

std::vector<fine::Term> attribute(ErlNifEnv *env, ExLazyHTML ex_lazy_html,
                                  ErlNifBinary name) {
  auto values = std::vector<fine::Term>();

  for (auto node : ex_lazy_html.resource->nodes) {
    if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
      auto element = lxb_dom_interface_element(node);

      auto has_attribute =
          lxb_dom_element_has_attribute(element, name.data, name.size);

      if (has_attribute) {
        size_t value_length;
        auto value = lxb_dom_element_get_attribute(element, name.data,
                                                   name.size, &value_length);
        auto value_term = make_new_binary(env, value_length, value);
        values.push_back(value_term);
      }
    }
  }

  return values;
}

FINE_NIF(attribute, 0);

std::vector<fine::Term> attributes(ErlNifEnv *env, ExLazyHTML ex_lazy_html) {
  auto list = std::vector<fine::Term>();

  for (auto node : ex_lazy_html.resource->nodes) {
    if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
      auto element = lxb_dom_interface_element(node);
      list.push_back(attributes_to_term(env, element, false));
    }
  }

  return list;
}

FINE_NIF(attributes, 0);

std::tuple<std::vector<ExLazyHTML>, bool> nodes(ErlNifEnv *env,
                                                ExLazyHTML ex_lazy_html) {
  auto list = std::vector<ExLazyHTML>();

  for (auto node : ex_lazy_html.resource->nodes) {
    list.push_back(ExLazyHTML(fine::make_resource<LazyHTML>(
        ex_lazy_html.resource->document_ref, std::vector({node}), true)));
  }

  return std::make_tuple(list, ex_lazy_html.resource->from_selector);
}

FINE_NIF(nodes, 0);

std::uint64_t num_nodes(ErlNifEnv *env, ExLazyHTML ex_lazy_html) {
  return ex_lazy_html.resource->nodes.size();
}

FINE_NIF(num_nodes, 0);

std::vector<fine::Term> tag(ErlNifEnv *env, ExLazyHTML ex_lazy_html) {
  auto values = std::vector<fine::Term>();

  for (auto node : ex_lazy_html.resource->nodes) {
    if (node->type == LXB_DOM_NODE_TYPE_ELEMENT) {
      auto element = lxb_dom_interface_element(node);

      size_t name_length;
      auto name = lxb_dom_element_qualified_name(element, &name_length);
      if (name == NULL) {
        throw std::runtime_error("failed to read tag name");
      }
      auto name_term = make_new_binary(env, name_length, name);
      values.push_back(name_term);
    }
  }

  return values;
}

FINE_NIF(tag, 0);

} // namespace lazy_html

FINE_INIT("Elixir.LazyHTML.NIF");
