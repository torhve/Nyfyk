var services = angular.module('Nyfyk.services', []);

function Item(entry, feedTitle, feedUrl) {
  //this.read = false;
  this.starred = false;
  this.selected = false;
  this.feedTitle = feedTitle;
  this.feedUrl = feedUrl;
  this.date = new Date(entry.pubDate*1000);
  this.read = entry.unread == false;

  angular.extend(this, entry);
}

function Feed(title) {
    this.unreadCount = 0;
    this.readCount = 0;
    this.title = title;
    this.selected = false;
}


Item.prototype.$$hashKey = function() {
  return this.id;
}


/**
 * ViewModel service representing all feed entries the state of the UI.
 */
services.factory('items', ['$http', function($http) {
  var items = {
    all: [],
    feeds: [],
    feedhash: {},
    filtered: [],
    selected: null,
    selectedIdx: null,
    readCount: 0,
    feedCount: 0,
    starredCount: 0,


    getItemsFromBackend: function() {
        /*
      $http.get('/nyfyk/api/items/').success(function(data) {
          console.log(data);
        $scope.feed = data;
      });
      //feedStore.getAll().then(function(feeds) {
      feedStore.getAll().then(function(feeds) {
      */
      $http.get('/nyfyk/api/items/').then(function(data) {
        var i = 0;

        items.all = [];
        items.feeds = [];
        items.feedhash = {};
        console.log('data', data);
        feed = data.data;

        angular.forEach(feed, function(entry) {
            var item = new Item(entry, entry.title, entry.url);
            items.all.push(item);
            i++;
            // maintain unique list of feed titles
            if(items.feedhash[entry.feedTitle] == undefined) {
                var feed = new Feed(entry.feedTitle);
                if(item.read)   feed.readCount++;
                if(item.unread) feed.unreadCount++;

                items.feedhash[entry.feedTitle] = feed;
                items.feeds.push(feed);
            }
        });
        console.log("Entries loaded from backend:", i);

        items.all.sort(function(entryA, entryB) {
            return entryB.pubDate - entryA.pubDate;
        });
        // Sort feeds
        //items.feeds.sort();

        // Default show unread
        items.filtered = items.all.filter(function(item) {
            return item.read === false;
        });

        items.readCount = items.all.reduce(function(count, item) { return item.read ? ++count : count; }, 0);
        items.starredCount = items.all.reduce(function(count, item) { return item.starred ? ++count : count; }, 0);
        items.selected = items.selected
            ? items.all.filter(function(item) { return item.id == items.selected.id; })[0]
            : null;
        items.reindexSelectedItem();
      });
    },


    prev: function() {
      if (items.hasPrev()) {
        items.selectItem(items.selected ? items.selectedIdx - 1 : 0);
      }
    },


    next: function() {
      if (items.hasNext()) {
        items.selectItem(items.selected ? items.selectedIdx + 1 : 0);
      }
    },


    hasPrev: function() {
      if (!items.selected) {
        return true;
      }
      return items.selectedIdx > 0;
    },


    hasNext: function() {
      if (!items.selected) {
        return true;
      }
      return items.selectedIdx < items.filtered.length - 1;
    },


    selectItem: function(idx) {
      // Unselect previous selection.
      if (items.selected) {
        items.selected.selected = false;
      }

      items.selected = items.filtered[idx];
      items.selectedIdx = idx;
      items.selected.selected = true;

      if (!items.selected.read) items.toggleRead();

    },


    toggleRead: function() {
      var item = items.selected,
          read = !item.read;

      item.read = read;
      //feedStore.updateEntryProp(item.feedUrl, item.id, 'read', read);
      console.log('toggleRead id:', item.id);
      $http.put('/nyfyk/api/items/'+item.id, {'unread': 0}).success(function(data) {
          console.log('Toggleread backend said', data);
      });
      items.readCount += read ? 1 : -1;

      items.feedhash[item.feedTitle].unreadCount += read ? -1 : 1;
      items.feedhash[item.feedTitle].readCount += read ? -1 : 1;
    },


    toggleStarred: function() {
      var item = items.selected,
          starred = !item.starred;

      item.starred = starred;
      console.log('Fixme', 'starred');
      //feedStore.updateEntryProp(item.feedUrl, item.id, 'starred', starred);
      items.starredCount += starred ? 1 : -1;
    },


    markAllRead: function() {
      items.filtered.forEach(function(item) {
        item.read = true;
        //feedStore.updateEntryProp(item.feedUrl, item.id, 'read', true);
      });
      items.readCount = items.filtered.length;
      $http.put('/nyfyk/api/items/', {'unread': 0}).success(function(data) {
          console.log('MarkAllRead backend said', data);
      });
    },


    filterBy: function(key, value) {
      items.filtered = items.all.filter(function(item) {
        return item[key] === value;
      });
      items.reindexSelectedItem();
    },

    selectFeed: function(idx) {
      var feed = items.feeds[idx];
      items.feeds.forEach(function(feed) {
          feed.selected = false;
      });
      feed.selected = true;
      
      items.filtered = items.all.filter(function(item) {
        return item.feedTitle == feed.title;
      });
      items.reindexSelectedItem();
    },


    clearFilter: function() {
      items.filtered = items.all;
      items.reindexSelectedItem();
    },


    reindexSelectedItem: function() {
      if (items.selected) {
        var idx = items.filtered.indexOf(items.selected);

        if (idx === -1) {
          if (items.selected) items.selected.selected = false;

          items.selected = null;
          items.selectedIdx = null;
        } else {
          items.selectedIdx = idx;
          items.selected.selected = true;
        }
      }
    },

    refreshFeeds: function() {
        $http.get('/nyfyk/api/refresh/').then(function(data) {
            console.log(data);
        });
    }
  };

  items.getItemsFromBackend();

  return items;
}]);


/**
 * Service that is in charge of scrolling in the app.
 */
services.factory('scroll', function($timeout) {
  return {
    pageDown: function() {
      var itemHeight = $('.entry.active').height() + 60;
      var winHeight = $(window).height();
      var curScroll = $('.entries').scrollTop();
      var scroll = curScroll + winHeight;

      if (scroll < itemHeight) {
        $('.entries').scrollTop(scroll);
        return true;
      }

      // already at the bottom
      return false;
    },

    toCurrent: function() {
      // Need the setTimeout to prevent race condition with item being selected.
      $timeout(function() {
        var curScrollPos = $('.summaries').scrollTop();
        var itemTop = $('.summary.active').offset().top - 60;
        $('.summaries').animate({'scrollTop': curScrollPos + itemTop}, 200);
        $('.entries article.active')[0].scrollIntoView();
      }, 0, false);
    }
  };
});


/**
 * Background page service.
 */
services.factory('bgPage', function() {
  return {
    /**
     * Initiates feed refresh.
     */
    refreshFeeds: function() {
      $http.get('/nyfyk/api/refresh/').then(function(data) {
          console.log(data);
      });
    }
  };
});
