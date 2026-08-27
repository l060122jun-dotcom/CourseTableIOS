const store = require('../../utils/store')
Page({ data: { document: {} }, onShow() { this.setData({ document: store.load() }) } })
