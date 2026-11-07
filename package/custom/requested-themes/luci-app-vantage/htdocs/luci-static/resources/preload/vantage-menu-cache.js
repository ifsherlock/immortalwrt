'use strict';
'require baseclass';
'require ui';

return baseclass.extend({
	__init__: function() {
		// LuCI reloads after applying settings but retains the tab's menu cache.
		document.addEventListener('uci-applied', function() {
			ui.menu.flushCache();
		});
	}
});
