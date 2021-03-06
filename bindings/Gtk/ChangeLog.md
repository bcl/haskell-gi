### 3.0.15

+ Fix introspection info for [uIManagerGetAction](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-UIManager.html#v:uIManagerGetAction), [uIManagerGetWidget](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-UIManager.html#v:uIManagerGetWidget), [actionGroupGetAction](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-ActionGroup.html#v:actionGroupGetAction), [textMarkGetName](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-TextMark.html#v:textMarkGetName) and [notebookGetTabLabel](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Notebook.html#v:notebookGetTabLabel). In all these cases the function can return NULL, but it was not marked as such in the introspection data.

+ Fix introspection data for [builderAddCallbackSymbol](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Builder.html#v:builderAddCallbackSymbol). The `callbackSymbol` argument was marked as `(scope async)`, which meant that it was safe to free after the first invokation, but this was not correct, and leads to [crashes](https://github.com/haskell-gi/haskell-gi/issues/104).

### 3.0.14

Update lower version bound on haskell-gi (>= 0.20.1).

### 3.0.13

Update nullable overrides to match gtk+ 3.22.11.

### 3.0.12

Fix a mistake in the introspection data in [widgetGetParentwindow](https://hackage.haskell.org/package/gi-gtk/docs/GI-Gtk-Objects-Widget.html#v:widgetGetParentWindow), where the return value was not properly annotated as nullable. Fixes [#90](https://github.com/haskell-gi/haskell-gi/issues/90).
