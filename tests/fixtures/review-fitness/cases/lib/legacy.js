promise.catch(() => {})
try { boot() } catch (e) {}
try { boot() } catch (e) { logger.error(e) }
