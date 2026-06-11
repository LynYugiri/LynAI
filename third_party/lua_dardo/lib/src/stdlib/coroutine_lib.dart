import '../api/lua_state.dart';
import '../api/lua_type.dart';
import '../vm/instructions.dart';

class CoroutineLib {
  static const Map<String, DartFunction?> _funcs = {
    'create': _create,
    'resume': _resume,
    'yield': _yield,
    'status': _status,
    'running': _running,
    'wrap': _wrap,
  };

  static int openCoroutineLib(LuaState ls) {
    ls.newLib(_funcs);
    return 1;
  }

  static int _create(LuaState ls) {
    ls.checkType(1, LuaType.luaFunction);
    ls.pushCoroutineFrom(1);
    return 1;
  }

  static int _resume(LuaState ls) {
    return ls.resumeCoroutine(1, ls.getTop() - 1);
  }

  static int _yield(LuaState ls) {
    ls.yieldCoroutine(ls.getTop());
  }

  static int _status(LuaState ls) {
    ls.pushString(ls.coroutineStatus(1));
    return 1;
  }

  static int _running(LuaState ls) {
    return ls.pushRunningCoroutine();
  }

  static int _wrap(LuaState ls) {
    _create(ls);
    ls.pushDartClosure(_wrapAux, 1);
    return 1;
  }

  static int _wrapAux(LuaState ls) {
    ls.pushValue(Instructions.luaUpvalueIndex(1));
    ls.insert(1);
    final n = ls.resumeCoroutine(1, ls.getTop() - 1);
    if (!ls.toBoolean(1)) {
      ls.remove(1);
      return ls.error();
    }
    ls.remove(1);
    return n - 1;
  }
}
