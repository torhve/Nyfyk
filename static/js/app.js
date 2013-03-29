var Nyfyk = angular.module('Nyfyk', ['Nyfyk.filters', 'Nyfyk.services', 'Nyfyk.directives' ]);

Nyfyk.run(function(items) {
    /*
  chrome.extension.onMessage.addListener(function(request) {
    if (request != 'feedsUpdated') return;
    items.getItemsFromDataStore();
  });
  */
});


// Main app controller
function AppController($scope, items, scroll, bgPage) {

  $scope.items = items;

  $scope.refresh = function() {
    //bgPage.refreshFeeds();
    items.refreshFeeds();
  };

  $scope.handleSpace = function() {
    if (!scroll.pageDown()) {
      items.next();
    }
  };

  $scope.$watch('items.selectedIdx', function(newVal) {
    if (newVal !== null) scroll.toCurrent();
  });
}


// Top Menu/Nav Bar
function NavBarController($scope, items) {

  $scope.showAll = function() {
    items.clearFilter();
  };

  $scope.showUnread = function() {
    items.filterBy('read', false);
  };

  $scope.showStarred = function() {
    items.filterBy('starred', true);
  };

  $scope.showRead = function() {
    items.filterBy('read', true);
  };
}


function PersonaCtrl($scope, personaSvc) {
    // initialize properties
    angular.extend($scope, { verified:false, error:false, email:"" });

    $scope.verify = function () {
        personaSvc.verify().then(function (email) {
            angular.extend($scope, { verified:true, error:false, email:email });
            $scope.status();
        }, function (err) {
            angular.extend($scope, { verified:false, error:err});
        });
    };

    $scope.logout = function () {
        personaSvc.logout().then(function () {
            angular.extend($scope, { verified:false, error:false});
        }, function (err) {
            $scope.error = err;
        });
    };

    $scope.status = function () {
        personaSvc.status().then(function (data) {
            // in addition to email, everything else returned by persona/status will be added to the scope
            // this could be the chance to expose data from your local DB, for example
            angular.extend($scope, data, { error:false, verified:!!data.email, email:data.email });
            // if we are verified refresh the item list
            // basicially means we just logged in
            if ($scope.verified) {
                $scope.items.getItemsFromBackend();
            }
        }, function (err) {
            $scope.error = err;
        });
    };

    // setup; check status once on init
    $scope.status();
}
PersonaCtrl.$inject = ["$scope", "personaSvc"];
