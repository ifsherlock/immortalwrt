'use strict';
'require baseclass';
'require ui';

/* Adapted from LuCI Material (Apache-2.0) for NeoBird's menu structure.
 * Copyright 2015-2017 Lutty Yang; Copyright 2021 2smile.
 * Uses the current ACL-filtered menu tree instead of the removed Lua dispatcher.
 */
return baseclass.extend({
	__init__() {
		if (L.env.sessionid)
			return ui.menu.load().then(tree => this.render(tree));
	},

	render(tree) {
		const modes = ui.menu.getChildren(tree);
		const mode = modes.find(child => child.name === L.env.requestpath[0]) || modes[0];
		const modeMenu = document.querySelector('#modemenu');
		for (const child of modes)
			modeMenu.appendChild(E('li', {}, [E('a', {
				'href': L.url(child.name), 'class': child === mode ? 'active' : ''
			}, [_(child.title)])]));
		if (modes.length > 1)
			modeMenu.parentElement.style.display = '';
		if (mode) {
			const menu = document.querySelector('#mainmenu');
			menu.appendChild(this.renderMainMenu(mode, [mode.name], 1));
			menu.style.display = '';
		}
		const path = L.env.dispatchpath.slice(0, 3);
		const node = this.lookup(tree, path);
		if (node)
			this.renderTabMenu(node, path);
		this.renderQuickMenu(tree);
		document.querySelector('.showSide').addEventListener('click', () => this.toggleSidebar());
		document.querySelector('.darkMask').addEventListener('click', () => this.toggleSidebar(false));
		window.addEventListener('resize', () => this.toggleSidebar(false));
	},

	lookup(tree, path) {
		let node = tree;
		for (const name of path) {
			node = ui.menu.getChildren(node).find(child => child.name === name);
			if (!node)
				return null;
		}
		return node;
	},

	renderMainMenu(tree, path, level) {
		const ul = E('ul', { 'class': level === 1 ? 'nav' : 'slide-menu' });
		for (const child of ui.menu.getChildren(tree)) {
			const selected = L.env.dispatchpath[level] === child.name;
			const expandable = level === 1 && ui.menu.getChildren(child).length > 0;
			const attrs = {
				'href': expandable ? '#' : L.url.apply(L, path.concat(child.name)),
				'class': level === 1 ? (expandable ? 'menu' : 'menu2') : '',
				'data-title': child.title
			};
			if (expandable) {
				attrs['aria-expanded'] = selected ? 'true' : 'false';
				attrs.click = ev => {
					ev.preventDefault();
					const open = ev.currentTarget.parentNode.classList.toggle('active');
					ev.currentTarget.setAttribute('aria-expanded', String(open));
				};
			}
			const li = E('li', { 'class': (level === 1 ? 'slide' : '') + (selected ? ' active' : '') }, [E('a', attrs, [_(child.title)])]);
			if (expandable)
				li.appendChild(this.renderMainMenu(child, path.concat(child.name), level + 1));
			ul.appendChild(li);
		}
		return ul;
	},

	renderTabMenu(tree, path) {
		const children = ui.menu.getChildren(tree);
		if (!children.length)
			return;
		const container = document.querySelector('#tabmenu');
		const ul = E('ul', { 'class': 'tabs' });
		let selected;
		for (const child of children) {
			const active = L.env.dispatchpath[path.length] === child.name;
			ul.appendChild(E('li', { 'class': 'tabmenu-item-' + child.name + (active ? ' active' : '') }, [
				E('a', { 'href': L.url.apply(L, path.concat(child.name)) }, [_(child.title)])
			]));
			if (active)
				selected = child;
		}
		container.appendChild(ul);
		container.style.display = '';
		if (selected)
			this.renderTabMenu(selected, path.concat(selected.name));
	},

	renderQuickMenu(tree) {
		const container = document.querySelector('#quickmenu');
		if (!container)
			return;
		const shortcuts = [
			{ paths: ['admin/status/overview'], icon: 'home' },
			{ paths: ['admin/services/momo', 'admin/services/nikki'], icon: 'ssr' },
			{ paths: ['admin/network/network'], icon: 'link' },
			{ paths: ['admin/status/realtime'], icon: 'rank' },
			{ paths: ['admin/system/admin'], icon: 'user' }
		];
		for (const shortcut of shortcuts) {
			const path = shortcut.paths.find(candidate => this.lookup(tree, candidate.split('/')));
			if (!path)
				continue;
			const node = this.lookup(tree, path.split('/'));
			container.appendChild(E('a', { 'href': L.url(path), 'title': _(node.title) }, [
				E('img', { 'src': L.env.media + '/images/' + shortcut.icon + '.png', 'alt': _(node.title) })
			]));
		}
	},

	toggleSidebar(force) {
		const open = window.innerWidth <= 992 && (force == null ? !document.body.classList.contains('neobird-menu-open') : force);
		document.body.classList.toggle('neobird-menu-open', open);
		document.querySelector('.showSide').setAttribute('aria-expanded', String(open));
	}
});
