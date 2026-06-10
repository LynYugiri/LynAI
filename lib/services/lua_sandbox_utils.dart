import 'package:lua_dardo/lua.dart';

const _dangerousLuaGlobals = [
  'os',
  'io',
  'package',
  'require',
  'dofile',
  'loadfile',
  'load',
  'debug',
  'collectgarbage',
];

void removeDangerousLuaGlobals(LuaState state) {
  for (final name in _dangerousLuaGlobals) {
    state.pushNil();
    state.setGlobal(name);
  }
}
