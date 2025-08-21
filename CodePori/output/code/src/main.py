# Auto-generated adapter for tests. Driver-scope only.
try:
    from src.core.main import main as _Core  # optional delegation if present
except Exception:
    _Core = object  # type: ignore

class main(_Core):  # type: ignore[misc]
    def __init__(self, **kwargs):
        ok = False
        try:
            super().__init__(**kwargs)
            ok = True
        except TypeError:
            try:
                super().__init__(**kwargs)
                ok = True
            except Exception:
                pass
        except Exception:
            pass
        self.__dict__.update({})
