module sourcemaps.output;
import sourcemaps.vlq;

import std.array;
import std.json;
import std.path : buildNormalizedPath;
import std.algorithm : find;
import std.file : exists, readText;
import std.stdio : writeln, stderr;
import std.format;
import dwarf.debugline;
import dwarf.debuginfo;

auto getPath(string compDir, const ref LineProgram program, uint fileIndex) {
  auto filepath = program.fileFromIndex(fileIndex);
  if (program.dirIndex(fileIndex) == 0)
    return compDir ~ "/" ~ filepath;
  return filepath;
}

auto toSourceMap(DebugLine line, DebugInfo info, uint codeSectionOffset, bool embed, string embedBaseUrl, bool includeSources, string[] includeSourcesPaths) {
  uint[string] sourceMap;
  Appender!(string[]) sources;
  Appender!(string[]) contents;
  Appender!(string[]) mappings;

  struct State {
    long address;
    int sourceId;
    int line;
    int column;
    State opBinaryRight(string op : "-")(ref State rhs) {
      return State(address-rhs.address,
                   sourceId-rhs.sourceId,
                   line-rhs.line,
                   column-rhs.column
                   );
    }
    string toVlq() {
      auto app = appender!string;
      app.put(encodeVlq(address));
      app.put(encodeVlq(sourceId));
      app.put(encodeVlq(line));
      app.put(encodeVlq(column));
      return app.data;
    }
  }

  auto correctPath(string filename) {
    if (includeSourcesPaths.length == 0)
      return filename;
    auto search = includeSourcesPaths.find!(path => exists(path~"/"~filename));
    if (search.empty)
      return filename;
    return search.front() ~ "/" ~ filename;
  }

  State prevState, state;
  foreach (idx, program; line.programs) {
    string compDir = info.units[idx].getCompDir();
    foreach (address; program.addressInfo) {
      if (address.line == 0)
        continue;
      state.line = address.line;
      state.column = address.column;
      state.address = address.address + codeSectionOffset;
      auto filepath = compDir.getPath(program, address.fileIndex).buildNormalizedPath;
      if (auto p = filepath in sourceMap) {
        state.sourceId = (*p);
      } else {
        state.sourceId = cast(int)sources.data.length;
        sourceMap[filepath] = state.sourceId;
        sources.put(filepath);
        if (includeSources) {
          if (!exists(filepath)) {
            stderr.writeln(format("Error: Cannot find %s", filepath));
          } else
            contents.put(readText(filepath));
        }
      }
      auto delta = state - prevState;
      mappings.put(delta.toVlq);
      prevState = state;
    }
  }

  JSONValue[] names;
  return JSONValue(["version": JSONValue(3),
                    "names": JSONValue(names),
                    "sourcesContents": JSONValue(contents.data),
                    "souces": JSONValue(sources.data),
                    "mappings": JSONValue(mappings.data.join(","))
                    ]);
}
