angular.module('nyfyk', []).
  config(['$routeProvider', function($routeProvider) {
  $routeProvider.
      when('/feeds', {templateUrl: 'feed-list.html',   controller: FeedListCtrl}).
      when('/feeds/:feedId', {templateUrl: 'feed.html', controller: FeedCtrl}).
      otherwise({redirectTo: '/feeds'});
}]);

