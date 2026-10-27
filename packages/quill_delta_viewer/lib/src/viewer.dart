import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quill_delta/quill_delta.dart';
import 'package:url_launcher/url_launcher.dart';

class QuillDeltaViewer extends StatelessWidget {
  /// The document delta to be rendered
  final Delta delta;

  const QuillDeltaViewer({Key? key, required this.delta}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return render(isolateLines(delta), context);
  }

  /// Splits all operations at newlines
  /// Newlines will be at the end of operations
  List<Operation> isolateLines(Delta delta) {
    final List<Operation> operations = [];
    for (var i = 0; i < delta.length; i++) {
      final op = delta.elementAt(i);
      var string = op.stringData;
      final split = <String>[];
      for (;;) {
        final index = string.indexOf("\n");
        if (index == -1) {
          split.add(string);
          break;
        }
        split.add(string.substring(0, index + 1));
        string = string.substring(index + 1);
      }
      operations.addAll(
        split.map(
          (s) => Operation.insert(
            s,
            op.attributes,
          ),
        ),
      );
    }
    return operations;
  }

  /// The whole message as one text, lines separated by real line breaks.
  ///
  /// It used to be a column with one text per line or paragraph. That looked
  /// the same, but selecting across lines and copying lost every line break
  /// (#20): a selection spanning several texts is joined without anything in
  /// between. One text keeps them. List items get a bullet at the start of
  /// their line instead of a row of their own.
  Widget render(List<Operation> ops, BuildContext context) {
    final spans = <InlineSpan>[];
    var line = <InlineSpan>[];

    void endLine(Map<String, dynamic>? blockAttributes) {
      if (blockAttributes?["list"] != null) {
        spans.add(const TextSpan(text: "•  "));
      }
      spans.addAll(line);
      spans.add(const TextSpan(text: "\n"));
      line = [];
    }

    for (final op in ops) {
      final text = op.stringData;
      if (text.endsWith("\n")) {
        final content = text.substring(0, text.length - 1);
        if (content.isNotEmpty) {
          line.add(
              renderText(Operation.insert(content, op.attributes), context));
        }
        endLine(op.attributes);
      } else if (text.isNotEmpty) {
        line.add(renderText(op, context));
      }
    }
    if (line.isNotEmpty) endLine(null);
    // Quill ends every document with a newline; trailing ones would only add
    // empty space below the text.
    while (spans.isNotEmpty &&
        spans.last is TextSpan &&
        (spans.last as TextSpan).text == "\n") {
      spans.removeLast();
    }
    return Text.rich(TextSpan(children: spans));
  }

  TextSpan renderText(Operation op, BuildContext context) {
    bool bold = false;
    bool italics = false;
    String? link;
    bool strike = false;
    bool underline = false;
    if (op.attributes != null) {
      bold = op.attributes!["bold"] == true;
      // Quill calls it "italic"; "italics" was what this used to check.
      italics = op.attributes!["italic"] == true ||
          op.attributes!["italics"] == true;
      link = op.attributes!["link"] as String?;
      strike = op.attributes!["strike"] == true;
      underline = op.attributes!["underline"] == true;
    }
    final isLink = link != null;

    final text = op.stringData;

    return TextSpan(
      text: text,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italics ? FontStyle.italic : null,
        decoration: TextDecoration.combine(
          [
            if (strike) TextDecoration.lineThrough,
            if (underline) TextDecoration.underline,
          ],
        ),
        color: isLink ? Theme.of(context).colorScheme.secondary : null,
      ),
      recognizer: isLink
          ? (TapGestureRecognizer()
            ..onTap = () {
              launchUrl(Uri.parse(link!));
            })
          : null,
    );
  }
}

extension DataHelper on Operation {
  String get stringData => data as String;
}
